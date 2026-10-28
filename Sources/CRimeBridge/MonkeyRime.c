#include "MonkeyRime.h"
#include "rime_api.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static RimeApi *api;
static void *library;
static unsigned owners;
static char *active_shared;
static char *active_user;

static int fail(char *error, size_t size, const char *message) {
  if (error && size) snprintf(error, size, "%s", message);
  return 0;
}

int monkey_rime_acquire(const char *library_path, const char *shared_path,
                        const char *user_path, char *error, size_t error_size) {
  if (owners) {
    if (strcmp(active_shared, shared_path) || strcmp(active_user, user_path))
      return fail(error, error_size, "Rime is already running with another data directory.");
    ++owners;
    return 1;
  }
  if (!library) {
    library = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
    if (!library) return fail(error, error_size, dlerror());
    RimeApi *(*get_api)(void) = (RimeApi *(*)(void))dlsym(library, "rime_get_api");
    if (!get_api) {
      dlclose(library);
      library = NULL;
      return fail(error, error_size, "The library does not export rime_get_api.");
    }
    api = get_api();
    if (!api || !RIME_PROVIDED(api, select_candidate_on_current_page)) {
      dlclose(library);
      library = NULL;
      api = NULL;
      return fail(error, error_size, "This version of librime is too old.");
    }
  }
  active_shared = strdup(shared_path);
  active_user = strdup(user_path);
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = active_shared;
  traits.user_data_dir = active_user;
  traits.distribution_name = "Monkey";
  traits.distribution_code_name = "monkey";
  traits.distribution_version = "0.1.0";
  traits.app_name = "rime.monkey";
  traits.min_log_level = 2;
  traits.log_dir = "";
  api->setup(&traits);
  api->initialize(&traits);
  // Deployment is performed once at launch, never in the keystroke path.
  if (api->start_maintenance(0)) api->join_maintenance_thread();
  owners = 1;
  return 1;
}

void monkey_rime_release(void) {
  if (!owners || --owners) return;
  api->cleanup_all_sessions();
  api->finalize();
  free(active_shared);
  free(active_user);
  active_shared = active_user = NULL;
  // Keep the dylib loaded: its logging/dependency libraries can register exit
  // handlers. Unloading them while those handlers remain registered is unsafe.
}

uintptr_t monkey_rime_create_session(void) {
  if (!owners) return 0;
  RimeSessionId session = api->create_session();
  if (!session) return 0;
  if (!api->select_schema(session, "monkey_pinyin")) {
    api->destroy_session(session);
    return 0;
  }
  api->set_option(session, "ascii_mode", 0);
  api->set_option(session, "ascii_punct", 0);
  return session;
}
void monkey_rime_destroy_session(uintptr_t session) {
  if (owners && session) api->destroy_session(session);
}
int monkey_rime_process(uintptr_t session, int key, int modifiers) {
  return owners && session ? api->process_key(session, key, modifiers) : 0;
}
int monkey_rime_select(uintptr_t session, int index) {
  return owners && session && index >= 0 ?
    api->select_candidate_on_current_page(session, (size_t)index) : 0;
}
int monkey_rime_commit_composition(uintptr_t session) {
  return owners && session ? api->commit_composition(session) : 0;
}
void monkey_rime_clear(uintptr_t session) {
  if (owners && session) api->clear_composition(session);
}
char *monkey_rime_take_commit(uintptr_t session) {
  if (!owners || !session) return NULL;
  RIME_STRUCT(RimeCommit, commit);
  if (!api->get_commit(session, &commit)) return NULL;
  char *copy = commit.text ? strdup(commit.text) : NULL;
  api->free_commit(&commit);
  return copy;
}
void monkey_rime_free_string(char *string) { free(string); }

MonkeyRimeSnapshot *monkey_rime_snapshot(uintptr_t session) {
  MonkeyRimeSnapshot *snapshot = calloc(1, sizeof(*snapshot));
  if (!snapshot) return NULL;
  snapshot->preedit = strdup("");
  snapshot->is_last_page = 1;
  if (!owners || !session) return snapshot;
  RIME_STRUCT(RimeContext, context);
  if (!api->get_context(session, &context)) return snapshot;
  free(snapshot->preedit);
  snapshot->preedit = strdup(context.composition.preedit ? context.composition.preedit : "");
  snapshot->candidate_count = context.menu.num_candidates;
  snapshot->candidates = calloc((size_t)snapshot->candidate_count, sizeof(char *));
  for (int i = 0; i < snapshot->candidate_count; ++i)
    snapshot->candidates[i] = strdup(context.menu.candidates[i].text ? context.menu.candidates[i].text : "");
  snapshot->highlighted_index = context.menu.highlighted_candidate_index;
  snapshot->page = context.menu.page_no;
  snapshot->is_last_page = context.menu.is_last_page;
  api->free_context(&context);
  return snapshot;
}
void monkey_rime_free_snapshot(MonkeyRimeSnapshot *snapshot) {
  if (!snapshot) return;
  free(snapshot->preedit);
  for (int i = 0; i < snapshot->candidate_count; ++i) free(snapshot->candidates[i]);
  free(snapshot->candidates);
  free(snapshot);
}
