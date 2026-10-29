# Monkey · 盲 key

Monkey 的命名带有「盲 key」的谐音趣味。视觉从键盘、触感与输入光标出发，不再使用「猴」字作为图标。

- 主图标：深靛蓝底、青柠色立体键帽，双拱 `m` 与光标的抽象组合。保留柔和的实体感，避免把设置做成卡通主题。
- 设置界面：墨色文字、暖白表面、克制的青柠强调，适配系统深浅模式。
- 输入源图标：同一双拱与光标轮廓的单色矢量版本，适合菜单栏小尺寸显示。

资源：`Resources/AppIcon.png`（带透明通道的原始主图）、`Resources/AppIcon.icns`（16～1024 像素 macOS 图标）、`Resources/MenuBarIcon.svg` 与 `Resources/monkey.pdf`（单色标记）。运行 `scripts/build-icons.sh` 可从主图与 SVG 重建派生产物。

主图使用内置 imagegen 生成。生成提示词：

```text
Use case: logo-brand. Create ONE finished premium macOS application icon for 'Monkey', an open-source Chinese Pinyin keyboard with optional translation. The name is a Chinese pun on '盲 key' (touch typing); the brand should feel like an independent contemporary creative tool, NOT a Chinese-character badge or a cartoon zoo app. Asset: square 1024x1024 production icon, clean actual alpha outside its silhouette. Composition: a large centered rounded-square midnight-indigo tile, about 88 percent canvas width, excellent dock-size silhouette. On it one tactile sculptural acid-lime keycap, a little three-dimensional depth but nearly front-facing. The keycap carries a bold custom dark-ink continuous double-arch symbol suggesting a lowercase m and a tactile blindfold/visor, followed by one small confident caret/cursor notch. Make the symbol simple and iconic, not typeset text. Contemporary warm soft studio light, precise rounded edges, restrained smooth ceramic/rubber material, subtle depth and soft internal shadow. Palette: midnight ink #171B2E, vibrant pale lime #D7F879, soft warm highlights. Sophisticated, playful, confident, minimal. Preserve large clean forms for 16px legibility. No Chinese characters, no '猴', no words, no labels, no letters outside the abstract emblem, no monkey face, no photograph, no extra icon grid, no watermarks, no UI mockup. Output only this single icon, with a truly transparent background outside the rounded tile.
```

实际生成主图为 1254 × 1254 像素，派生尺寸通过 macOS `sips` 与 `iconutil` 生成；图像内容和透明通道保持不变。
