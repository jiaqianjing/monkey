#ifndef MONKEY_RIME_H
#define MONKEY_RIME_H
#include <stdint.h>
#include <stddef.h>

// All calls are serialized by the Swift main actor. The underlying Rime engine
// is process-global, while sessions remain specific to each text client.
int monkey_rime_acquire(const char *library_path, const char *shared_path,
                        const char *user_path, char *error, size_t error_size);
void monkey_rime_release(void);
uintptr_t monkey_rime_create_session(void);
void monkey_rime_destroy_session(uintptr_t session);
int monkey_rime_process(uintptr_t session, int key, int modifiers);
int monkey_rime_select(uintptr_t session, int index);
int monkey_rime_commit_composition(uintptr_t session);
int monkey_rime_forget_candidate(uintptr_t session, int index);
int monkey_rime_change_page(uintptr_t session, int backward);
void monkey_rime_clear(uintptr_t session);
char *monkey_rime_take_commit(uintptr_t session);
void monkey_rime_free_string(char *string);

typedef struct MonkeyRimeSnapshot {
  char *preedit;
  char *raw_input;
  char **candidates;
  char **comments;
  int cursor_pos;
  size_t raw_cursor_pos;
  int candidate_count;
  int highlighted_index;
  int page;
  int is_last_page;
} MonkeyRimeSnapshot;
MonkeyRimeSnapshot *monkey_rime_snapshot(uintptr_t session);
void monkey_rime_free_snapshot(MonkeyRimeSnapshot *snapshot);
#endif
