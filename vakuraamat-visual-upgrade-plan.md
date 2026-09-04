# Vakuraamat — visual upgrade plan

**Purpose:** evaluate and sequence the changes that make the real ground look real. Personal
project: any licence that permits personal use is acceptable; counts and attribution noted anyway.
Each step ends in a screenshot comparison and an FPS number at 1600×900 on the M5 Pro
(baseline: 75–105 FPS in the world scene). Steps are independent unless noted.

| # | Item | Source / tool | Licence | Godot 4.7 | Effort | Expected gain | Risk |
|---|---|---|---|---|---|---|---|
| 0 | Buildings floating on slopes | ours | – | – | 1 h | fixes an obvious wrongness | none |
| 1 | Lighting: SDFGI, SSIL, volumetric fog, TAA, exposure, Sky3D tuning | built-in Forward+ | – | yes | 0.5 day | largest single change in look | FPS cost; SDFGI + instancer ghosting |
| 2 | Trees: real species, LODs, impostors | Poly Haven pine (CC0), Tree3D (MIT) for birch/bushes, Octahedral Impostors (MIT, godot4 branch) | all permissive | Tree3D 4.5+; impostors unverified on 4.7 | 2 days | forest stops reading as painted | impostor addon age; 4.8k trees × mesh cost |
| 3 | Grass: wind, colour variation, density | SimpleGrassTextured (MIT) or Terrain3D instancer + wind shader | MIT | updated 2026-06 | 1 day | fields stop looking like cards on felt | two vegetation systems to keep in sync |
| 4 | Water: the pond, ditches | Godot 4 realistic water port (MIT) for the pond; Waterways (MIT, godot4 branch) if a stream is added | MIT | ports unverified on 4.7 | 1 day | reflections sell the whole scene | pond outline must come from the orthophoto |
| 5 | Ground: road decals, normal detail, wetness | built-in Decal, our drape shader | – | yes | 0.5 day | roads and yards stop looking flat | none |
| 6 | Buildings: textures instead of flat colours | ambientCG (CC0) plaster/wood/tile | CC0 | – | 1 day | manor stops reading as a box | UV work in the Blender scripts |

Deliberately not on the list: Megascans (free tier is Unreal/USD-oriented and the all-engines
free period ended 2024), HDR output and AreaLight3D (new in 4.7, irrelevant outdoors),
Spatial Gardener (overlaps Terrain3D's instancer).

## Method per step
1. Verify the addon loads on 4.7.2 headless before integrating (as done for Terrain3D and inkgd).
2. Integrate through the existing pipeline: trees and grass through `scatter_vegetation.gd`,
   ground through `ortho_drape.gdshader`, props through `gen_era_scenes.py`.
3. Capture the same three views before and after (`tools/verify_spike.sh` style) and log FPS.
4. Keep the tests green: `boot`, `playthrough`, `farming`, `hunting`, `economy`.
5. Commit per step with the FPS numbers in the message.

## Order
0 → 1 → 2 → 3 → 4 → 5 → 6. Steps 1 and 0 first because they are cheap and change every
screenshot; 2 because the user named trees as the worst; 3–6 as time allows.

## Status
- [ ] 0 buildings grounded
- [ ] 1 lighting
- [ ] 2 trees
- [ ] 3 grass
- [ ] 4 water
- [ ] 5 ground decals
- [ ] 6 building textures
