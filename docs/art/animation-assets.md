# Animation assets: generated art

Decision (@gillzj00, 2026-10-01): the art rule is now **original or generated art, no stock downloads**. The event shows (`ios/Wad/Events/Stage`) keep their SpriteKit motion, particles, sound and haptics; the drawn subjects can be replaced by generated transparent PNGs. This file is the asset pack: what to generate, the prompts, and where the files go.

## Format

- PNG with a transparent background, 1024 x 1024, subject filling about 80 percent of the frame, nothing cropped at the edges.
- One subject or part per file, in the pose listed below. Parts that move separately (a jaw, a wing) are separate files drawn from the same angle so they line up.
- File names are exact; put them in `ios/Wad/Resources/Art/<event>/`. The folder is read as a bundle resource and each file becomes an `SKTexture` with the same name (`Art+Generated.swift`, to be written when the files exist).
- Generate every image with the same style prefix so the nine shows look like one artist drew them.
- Check each image at phone size: the silhouette must read from across a table.

## Style prefix (put in front of every prompt)

"Cel-shaded cartoon illustration, bold black ink outline, flat colors with one darker shadow tone from a top-left light and a thin rim light, slightly exaggerated proportions, death metal poster style, isolated on a transparent background, no text, no watermark, no background scenery."

Negative prompt where the tool takes one: "photorealistic, 3D render, blurry, text, watermark, background, cropped, extra fingers, extra limbs."

## Palette words

Backgrounds and text stay the app's: near-black charcoal, blood red, bone white, ember orange. Subjects use natural colors: bone white with warm grey shadows, grey wolf fur, dark brown eagle, white albatross.

## Subjects and files

### holeInOne
- `flagstick.png`: red flag with a small white skull on a thin bone-white pole, hanging straight.
- `ball.png`: white golf ball with a visible dimple pattern and a crescent shadow.
- `cork.png`: champagne cork with its wire cage, flying, small foam at the base.
- `bottle.png`: dark green champagne bottle with a red skull label and gold foil, upright, unopened.

### albatross
- `albatross-body.png`: albatross from the side, white body, pale pink-yellow long hooked bill, dark eye patch, feet tucked, no wings.
- `albatross-wing-up.png`, `albatross-wing-down.png`: one very long narrow wing (high aspect ratio) with dark tips, up stroke and down stroke, drawn from the same side view as the body, attached point at the shoulder on the left edge.

### eagle
- `eagle-body.png`: bald eagle from the side, white head with a fierce brow, hooked yellow beak, dark brown body, fanned white tail, yellow talons, no wings.
- `eagle-wing-up.png`, `eagle-wing-down.png`: one dark brown wing with three feather layers and splayed primaries, up and down stroke, same angle as the body.

### greenie
- `green-surface.png`: an oval putting green seen from a low angle with a hole and a short flagstick, lush green, cel-shaded. (Reused by the crater; the explosion stays as particles.)
- `turf-chunk.png`: a single flying clump of turf with roots and soil.
- `ball.png`: as in holeInOne (copy the file).

### wadTaken
- `skeleton-hand-open.png`: a skeletal right hand reaching up, palm facing the viewer, fingers spread and slightly curled, anatomically believable (carpals at the wrist, five fanned metacarpals, three phalanges per finger, two for the thumb, hourglass bones with knuckle flare, dark gaps at the joints), bone white with warm grey shadow.
- `bill.png`: a cartoon banknote, green, with a skull portrait in the oval and "1" in the corners.
- `coin.png`: gold coin with an embossed rim and a skull, face on.
- `skull-1.png`, `skull-2.png`, `skull-3.png`: three human skulls, three-quarter view, slightly different angles, for the pile.

### skinWon
- `flesh-hand-open.png`: a human right hand, palm facing the viewer, fingers spread, cel-shaded skin, nails and knuckle creases.
- `skin-flap.png`: a loose peeled sheet of skin, same hand shape, drooping, with a pink underside.
- `skeleton-hand-open.png`: the same file as wadTaken (copy it).
- `dagger.png`: a straight dagger with a dark grip and a bright blade, horizontal, point right.
- `blood-drop.png`: one teardrop blood drop with an ink outline and a highlight.

### wolfHoleWon
- `wolf-head.png`: grey wolf head, front three-quarter view, teeth bared, upper jaw only (mouth open, lower jaw missing), ember orange eyes with slit pupils, fur in three tones, ears up.
- `wolf-jaw.png`: the matching lower jaw with fangs, tongue and gums, same angle, so it can hinge under the head.

### snowman
- `snowman-head.png`: a snowball head with coal eyes, a carrot nose and a crooked coal smile.
- `snowman-middle.png`: the middle snowball with three coal buttons and a red scarf.
- `snowman-base.png`: the largest snowball.
- `top-hat.png`: black top hat with a red band, slightly tilted.
- `ice-shard.png`: one faceted chunk of ice.

### birdie
- `skeleton-fist-finger.png`: a skeletal right hand making a fist with the middle finger fully extended, seen from the back of the hand, same anatomy rules as the open hand, nothing visible through the curled fingers.
- `bird.png`: a small red cartoon bird perched, side view, facing right.

## After the files exist

1. Add the folder under `ios/project.yml` resources, run `xcodegen`.
2. Write `Art+Generated.swift`: `SKTexture(imageNamed:)` by file name with a fallback to the code-drawn texture when a file is missing, so the shows never break.
3. Swap each scene's subject nodes to the generated textures, keeping the motion, emitters, sound and haptics. Re-check Reduce Motion poster frames.
4. Keep the code-drawn art as the fallback until every file is in.
