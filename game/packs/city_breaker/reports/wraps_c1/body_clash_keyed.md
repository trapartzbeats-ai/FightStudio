# Body clash report (Collision Wrap) - clip poses as keyed

Every clip each fighter plays, every frame, on its Collision Wrap (`data/wraps/<key>.collide.json`). A **self** clash is a
body part going into the fighter's own body deeper than it does at rest; a **floor** clash is a part under the floor in a
planted clip. Depths in cm at match height, tolerance 1.0 cm. Frames: first-last (how many).

| fighter | clips | with self clashes | with floor clashes | frames |
|---|---|---|---|---|
| vix | 83 | 51 | 37 | 2996 |
| carter | 83 | 82 | 7 | 3134 |
| goat | 83 | 19 | 7 | 3184 |
| slum | 83 | 15 | 0 | 3143 |
| al | 83 | 81 | 48 | 3188 |
| guru | 83 | 59 | 46 | 3034 |
| bigbill | 83 | 71 | 12 | 3101 |
| rhino | 83 | 69 | 51 | 3275 |
| hype | 83 | 82 | 8 | 3068 |
| vic | 83 | 69 | 8 | 3038 |
| kat | 83 | 83 | 48 | 3046 |
| **all** | **913** | **681** | **272** | **34207** |

## What clashes most

| parts | clips | worst cm |
|---|---|---|
| chest - elbow | 516 | 31.3 |
| hand - head | 505 | 31.2 |
| elbow - head | 391 | 25.5 |
| foot under the floor | 383 | 12.6 |
| chest - hand | 201 | 31.7 |
| arm - head | 199 | 22.4 |
| ear - neck | 162 | 9.7 |
| elbow - leg | 151 | 33.5 |
| leg - torso | 137 | 13.9 |
| ear - elbow | 134 | 12.9 |
| leg - tail | 129 | 15.2 |
| arm - neck | 129 | 25.3 |
| arm - torso | 128 | 20.9 |
| hand - leg | 110 | 26.8 |
| chest - hips | 99 | 43.8 |
| ear - hand | 93 | 8.5 |
| chest - leg | 90 | 30.7 |
| hand - hand | 85 | 24.4 |
| arm - leg | 82 | 29.8 |
| chest - head | 81 | 10.6 |
| elbow - neck | 63 | 26.7 |
| foot - leg | 61 | 16.6 |
| hand - neck | 60 | 16.0 |
| hand - torso | 53 | 16.5 |
| elbow - hand | 51 | 21.5 |
| elbow - hips | 46 | 20.6 |
| hand - knee | 46 | 17.3 |
| elbow - torso | 45 | 11.2 |
| foot - knee | 43 | 16.7 |
| hips - knee | 42 | 18.5 |

## Worst 60

| cm | fighter | clip | kind | parts | frames |
|---|---|---|---|---|---|
| 118.1 | kat | a_kat_bthrow | floor | head | 11-24 (14) worst 21 |
| 114.2 | kat | a_kat_bthrow | floor | earL3 | 12-24 (13) worst 21 |
| 112.1 | kat | a_kat_bthrow | floor | earR2 | 12-23 (12) worst 21 |
| 108.0 | kat | a_kat_bthrow | floor | earR3 | 12-24 (13) worst 21 |
| 106.2 | kat | a_kat_bthrow | floor | earL2 | 12-23 (12) worst 21 |
| 105.2 | kat | a_kat_bthrow | floor | tail3 | 9-22 (14) worst 20 |
| 105.1 | kat | a_kat_bthrow | floor | handR | 11-24 (14) worst 21 |
| 95.0 | kat | a_kat_bthrow | floor | armR | 12-23 (12) worst 21 |
| 94.5 | kat | a_kat_bthrow | floor | neck | 17-23 (7) worst 21 |
| 94.2 | kat | a_kat_bthrow | floor | elbowR | 11-24 (14) worst 21 |
| 93.0 | kat | a_kat_bthrow | floor | chest | 16-23 (8) worst 21 |
| 88.7 | kat | a_kat_bthrow | floor | armL | 12-23 (12) worst 21 |
| 80.8 | kat | a_kat_bthrow | floor | tail2 | 10-22 (13) worst 20 |
| 76.9 | kat | a_kat_bthrow | floor | handL | 13-24 (12) worst 21 |
| 75.6 | kat | a_kat_bthrow | floor | elbowL | 13-24 (12) worst 21 |
| 74.7 | kat | a_kat_bthrow | floor | tail | 10-23 (14) worst 20 |
| 70.1 | kat | a_kat_bthrow | floor | torso | 18-23 (6) worst 21 |
| 63.3 | kat | a_kat_bthrow | floor | breastL2 | 19-23 (5) worst 21 |
| 55.8 | al | a_al_land | floor | tail3 | 0-5 (6) worst 3 |
| 53.8 | kat | a_kat_bthrow | floor | legR | 11-24 (14) worst 21 |
| 51.8 | kat | a_kat_bthrow | floor | hips | 19-23 (5) worst 21 |
| 47.2 | kat | a_kat_bthrow | floor | legL | 13-23 (11) worst 21 |
| 43.8 | rhino | a_rhino_land | self | hips / chest | 0-10 (11) worst 3 |
| 39.9 | vix | a_vix_land | floor | tail3 | 1-5 (5) worst 3 |
| 33.5 | rhino | a_pass | self | legR / elbowR | 2-19 (18) worst 10 |
| 33.2 | rhino | a_pass | self | legL / elbowL | 0-20 (21) worst 7 |
| 31.7 | al | a_al_special_spin | self | chest / handR | 0-12 (13) worst 11 |
| 31.3 | al | a_al_damage_fall | self | chest / elbowR | 0-24 (25) worst 12 |
| 31.2 | vic | a_vic_escape_f | self | handR / head | 4-46 (43) worst 40 |
| 31.2 | vic | a_vic_escape_b | self | handR / head | 4-46 (43) worst 40 |
| 31.1 | vic | a_vic_air_dodge_b | self | handR / head | 4-53 (50) worst 16 |
| 31.1 | vic | a_vic_air_dodge_f | self | handR / head | 4-53 (50) worst 12 |
| 30.7 | rhino | a_rhino_land | self | legL / chest | 2-6 (5) worst 3 |
| 30.2 | vic | a_vic_cliff_climb | self | handR / head | 0-18 (19) worst 7 |
| 30.0 | rhino | a_pass | self | hips / chest | 0-24 (25) worst 8 |
| 29.9 | al | a_al_dtilt | floor | tail3 | 7-18 (12) worst 7 |
| 29.8 | rhino | a_rhino_land | self | legL / armL | 2-5 (4) worst 3 |
| 29.3 | rhino | a_rhino_land | self | legR / armR | 2-5 (4) worst 3 |
| 29.1 | rhino | a_rhino_land | self | legR / elbowR | 0-5 (6) worst 2 |
| 28.7 | vic | a_special_guard | self | handR / head | 0-10 (11) worst 2 |
| 28.5 | rhino | a_rhino_land | self | legR / chest | 1-5 (5) worst 3 |
| 27.8 | al | a_al_land | self | legR / chest | 1-5 (5) worst 3 |
| 27.8 | vic | a_vic_cliff_catch | self | handR / head | 0-10 (11) worst 10 |
| 27.5 | rhino | a_rhino_land | self | kneeR / elbowR | 2-5 (4) worst 3 |
| 26.8 | kat | a_fall_special | self | legR / handR | 0-48 (49) worst 24 |
| 26.7 | hype | a_hype_damage_fall | self | elbowR / neck | 6-16 (11) worst 11 |
| 26.2 | al | a_ottotto | self | chest / elbowR | 4-36 (33) worst 23 |
| 25.8 | al | a_al_dash_attack | self | hips / chest | 2-33 (32) worst 6 |
| 25.5 | carter | a_carter_dair | self | elbowR / head | 0-30 (31) worst 22 |
| 25.4 | al | a_al_land | self | legL / chest | 2-5 (4) worst 3 |
| 25.3 | vic | a_item_smash | self | armR / neck | 2-21 (20) worst 11 |
| 25.2 | vic | a_vic_grab_wait_up | self | handR / head | 0-24 (25) worst 12 |
| 25.1 | vic | a_item_smash | self | handR / head | 0-47 (8) worst 2 |
| 25.1 | kat | a_kat_bthrow | floor | kneeR | 21-24 (4) worst 23 |
| 24.6 | al | a_al_land | self | chest / elbowR | 0-10 (11) worst 3 |
| 24.4 | al | a_al_special_spin | self | chest / elbowR | 0-12 (13) worst 2 |
| 24.4 | rhino | a_rhino_damage_fall | self | handL / handR | 5-19 (5) worst 6 |
| 24.2 | al | a_al_dash | floor | tail3 | 3-14 (8) worst 4 |
| 24.2 | al | a_al_run | floor | tail3 | 3-21 (14) worst 18 |
| 24.0 | vic | a_item_throw | self | handR / head | 0-16 (4) worst 1 |

## Bends past natural limits (the clip's own keys)

Joints the clip itself turns past the rig limits (`data/animator_rig.json`), in degrees past the limit. The Body Solve
never pushes these further; fixing them is a clip edit (Fight Studio clamps to the limits when you pose).

| joint axis | clips | worst degrees |
|---|---|---|
| fingers x | 598 | 25 |
| fingers z | 576 | 9 |
| index x | 382 | 25 |
| pinky x | 382 | 25 |
| pinky z | 364 | 9 |
| index z | 364 | 9 |
| ring x | 212 | 25 |
| ring z | 202 | 9 |
| elbow z | 110 | 24 |
| leg x | 102 | 46 |
| hand z | 88 | 34 |
| hand x | 66 | 53 |
| head x | 59 | 19 |
| arm x | 53 | 46 |
| knee y | 44 | 15 |
| chest x | 39 | 34 |
| elbow x | 33 | 10 |
| foot x | 26 | 70 |
| knee z | 22 | 5 |
| torso x | 17 | 13 |
| foot z | 11 | 3 |

| degrees | fighter | clip | joint axis | frames |
|---|---|---|---|---|
| 70 | guru | w_run | footR x | 0-40 (12) worst 5 |
| 70 | vic | w_run | footL x | 19-29 (11) worst 25 |
| 70 | rhino | w_run | footR x | 0-40 (12) worst 5 |
| 70 | guru | w_run | footL x | 19-29 (11) worst 25 |
| 70 | vic | w_run | footR x | 0-40 (12) worst 5 |
| 70 | rhino | w_run | footL x | 19-29 (11) worst 25 |
| 70 | bigbill | w_run | footL x | 19-29 (11) worst 25 |
| 70 | slum | w_run | footL x | 19-29 (11) worst 25 |
| 70 | bigbill | w_run | footR x | 0-40 (12) worst 5 |
| 70 | vix | w_run | footR x | 0-40 (12) worst 5 |
| 70 | carter | w_run | footR x | 0-40 (12) worst 5 |
| 70 | vix | w_run | footL x | 19-29 (11) worst 25 |
| 70 | slum | w_run | footR x | 0-40 (12) worst 5 |
| 70 | goat | w_run | footR x | 0-40 (12) worst 5 |
| 70 | hype | w_run | footL x | 19-29 (11) worst 25 |
| 70 | hype | w_run | footR x | 0-40 (12) worst 5 |
| 70 | al | w_run | footR x | 0-40 (12) worst 5 |
| 70 | kat | w_run | footL x | 19-29 (11) worst 25 |
| 70 | kat | w_run | footR x | 0-40 (12) worst 5 |
| 70 | goat | w_run | footL x | 19-29 (11) worst 25 |
| 70 | al | w_run | footL x | 19-29 (11) worst 25 |
| 70 | carter | w_run | footL x | 19-29 (11) worst 25 |
| 53 | guru | a_guru_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | kat | a_kat_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | al | a_al_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | slum | a_slum_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | vix | a_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | hype | a_hype_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | rhino | a_rhino_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | bigbill | a_bigbill_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | vic | a_vic_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | goat | a_goat_cliff_wait | handR x | 0-48 (49) worst 0 |
| 53 | carter | a_carter_cliff_wait | handR x | 0-48 (49) worst 0 |
| 46 | guru | a_guru_jab3 | legR x | 5-13 (9) worst 5 |
| 46 | carter | a_carter_dsmash | legL x | 25-36 (12) worst 27 |
| 46 | carter | a_carter_bthrow | legL x | 15-25 (11) worst 17 |
| 46 | bigbill | a_bigbill_usmash | armR x | 29-40 (12) worst 35 |
| 46 | vix | a_vix_bair | legL x | 4-25 (22) worst 4 |
| 46 | rhino | a_rhino_special_punch | armR x | 2-6 (5) worst 5 |
| 43 | kat | a_kat_dsmash | legR x | 8-23 (16) worst 8 |
