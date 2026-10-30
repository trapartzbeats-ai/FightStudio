# Body clash report (Collision Wrap C0)

Every clip each fighter plays, every frame, on its Collision Wrap (`data/wraps/<key>.collide.json`). A **self** clash is a
body part going into the fighter's own body deeper than it does at rest; a **floor** clash is a part under the floor in a
planted clip. Depths in cm at match height, tolerance 1.0 cm. Frames: first-last (how many).

| fighter | clips | with self clashes | with floor clashes | frames |
|---|---|---|---|---|
| vix | 83 | 50 | 37 | 2996 |
| carter | 83 | 81 | 7 | 3134 |
| goat | 83 | 17 | 7 | 3184 |
| slum | 83 | 23 | 0 | 3143 |
| al | 83 | 82 | 48 | 3188 |
| guru | 83 | 78 | 46 | 3034 |
| bigbill | 83 | 78 | 12 | 3101 |
| rhino | 83 | 69 | 51 | 3275 |
| hype | 83 | 82 | 8 | 3068 |
| vic | 83 | 69 | 8 | 3038 |
| kat | 83 | 83 | 48 | 3046 |
| **all** | **913** | **712** | **272** | **34207** |

## What clashes most

| parts | clips | worst cm |
|---|---|---|
| chest - elbow | 532 | 31.5 |
| hand - head | 442 | 35.7 |
| foot under the floor | 383 | 12.6 |
| elbow - head | 364 | 31.9 |
| chest - hand | 218 | 31.7 |
| arm - head | 218 | 20.5 |
| leg - tail | 216 | 17.9 |
| elbow - leg | 177 | 32.7 |
| foot - leg | 168 | 22.3 |
| ear - elbow | 158 | 16.3 |
| leg - torso | 134 | 9.4 |
| hand - leg | 133 | 29.2 |
| chest - leg | 129 | 29.6 |
| arm - torso | 123 | 27.7 |
| arm - leg | 112 | 29.3 |
| arm - neck | 104 | 25.5 |
| chest - hips | 99 | 43.8 |
| ear - hand | 99 | 8.5 |
| hand - hand | 85 | 24.4 |
| chest - head | 82 | 10.6 |
| hand - neck | 81 | 13.7 |
| leg under the floor | 72 | 68.2 |
| ear - neck | 65 | 10.8 |
| elbow - neck | 58 | 22.3 |
| knee - leg | 54 | 23.7 |
| elbow - torso | 52 | 16.3 |
| elbow - hand | 52 | 22.6 |
| hand - knee | 48 | 17.3 |
| foot - knee | 48 | 17.5 |
| elbow - hips | 47 | 20.6 |

## Worst 60

| cm | fighter | clip | kind | parts | frames |
|---|---|---|---|---|---|
| 118.1 | kat | a_kat_bthrow | floor | head | 11-24 (14) worst 21 |
| 115.1 | kat | a_kat_bthrow | floor | earR2 | 12-23 (12) worst 21 |
| 114.2 | kat | a_kat_bthrow | floor | earL3 | 12-24 (13) worst 21 |
| 108.0 | kat | a_kat_bthrow | floor | earR3 | 12-24 (13) worst 21 |
| 105.2 | kat | a_kat_bthrow | floor | tail3 | 9-22 (14) worst 20 |
| 105.1 | kat | a_kat_bthrow | floor | handR | 11-24 (14) worst 21 |
| 104.0 | kat | a_kat_bthrow | floor | earL2 | 13-24 (12) worst 21 |
| 96.5 | kat | a_kat_bthrow | floor | elbowR | 11-24 (14) worst 21 |
| 95.9 | kat | a_kat_bthrow | floor | armR | 12-23 (12) worst 21 |
| 94.5 | kat | a_kat_bthrow | floor | neck | 17-23 (7) worst 21 |
| 93.0 | kat | a_kat_bthrow | floor | chest | 16-23 (8) worst 21 |
| 90.2 | kat | a_kat_bthrow | floor | armL | 13-23 (11) worst 21 |
| 80.9 | kat | a_kat_bthrow | floor | tail2 | 10-22 (13) worst 20 |
| 76.9 | kat | a_kat_bthrow | floor | handL | 13-24 (12) worst 21 |
| 76.3 | kat | a_kat_bthrow | floor | elbowL | 13-24 (12) worst 21 |
| 74.7 | kat | a_kat_bthrow | floor | tail | 10-23 (14) worst 20 |
| 70.1 | kat | a_kat_bthrow | floor | torso | 18-23 (6) worst 21 |
| 68.2 | kat | a_kat_bthrow | floor | legL | 11-23 (13) worst 20 |
| 67.6 | kat | a_kat_bthrow | floor | legR | 10-24 (15) worst 20 |
| 63.3 | kat | a_kat_bthrow | floor | breastL2 | 19-23 (5) worst 21 |
| 55.8 | al | a_al_land | floor | tail3 | 0-5 (6) worst 3 |
| 51.8 | kat | a_kat_bthrow | floor | hips | 19-23 (5) worst 21 |
| 43.8 | rhino | a_rhino_land | self | hips / chest | 0-10 (11) worst 3 |
| 39.9 | vix | a_vix_land | floor | tail3 | 1-5 (5) worst 3 |
| 35.7 | bigbill | a_item_smash | self | handR / head | 0-47 (10) worst 2 |
| 32.7 | rhino | a_pass | self | legL / elbowL | 0-21 (22) worst 7 |
| 32.7 | rhino | a_pass | self | legR / elbowR | 0-21 (22) worst 10 |
| 32.6 | bigbill | a_bigbill_fair | self | handR / head | 0-34 (14) worst 4 |
| 31.9 | bigbill | a_bigbill_uair | self | elbowR / head | 0-18 (19) worst 14 |
| 31.7 | al | a_al_special_spin | self | chest / handR | 0-12 (13) worst 11 |
| 31.5 | al | a_al_damage_fall | self | chest / elbowR | 0-24 (25) worst 12 |
| 31.3 | bigbill | a_bigbill_usmash | self | handR / head | 21-44 (19) worst 42 |
| 31.2 | vic | a_vic_escape_f | self | handR / head | 4-46 (43) worst 40 |
| 31.2 | vic | a_vic_escape_b | self | handR / head | 4-46 (43) worst 40 |
| 31.1 | vic | a_vic_air_dodge_b | self | handR / head | 4-53 (50) worst 16 |
| 31.1 | vic | a_vic_air_dodge_f | self | handR / head | 4-53 (50) worst 27 |
| 31.0 | bigbill | a_bigbill_dash_attack | self | elbowR / head | 2-29 (28) worst 25 |
| 31.0 | bigbill | a_bigbill_fthrow | self | elbowR / head | 1-15 (15) worst 14 |
| 31.0 | bigbill | a_bigbill_air_dodge_b | self | handR / head | 3-55 (53) worst 6 |
| 31.0 | bigbill | a_bigbill_air_dodge_f | self | handR / head | 3-55 (53) worst 6 |
| 30.9 | bigbill | a_bigbill_special_rise | self | handR / head | 4-36 (33) worst 31 |
| 30.8 | bigbill | a_bigbill_dash_attack | self | handR / head | 2-28 (27) worst 23 |
| 30.8 | bigbill | a_bigbill_fair | self | elbowR / head | 0-34 (14) worst 4 |
| 30.6 | bigbill | a_bigbill_uair | self | handR / head | 0-18 (19) worst 1 |
| 30.4 | bigbill | a_item_throw | self | handR / head | 0-16 (6) worst 1 |
| 30.2 | vic | a_vic_cliff_climb | self | handR / head | 0-18 (19) worst 7 |
| 30.1 | bigbill | a_bigbill_cliff_climb | self | handR / head | 0-21 (22) worst 5 |
| 30.1 | bigbill | a_bigbill_usmash | self | elbowR / head | 20-45 (19) worst 25 |
| 30.0 | rhino | a_pass | self | hips / chest | 0-24 (25) worst 8 |
| 29.9 | al | a_al_dtilt | floor | tail3 | 7-18 (12) worst 7 |
| 29.9 | bigbill | a_bigbill_grab_wait_up | self | handR / head | 0-24 (25) worst 0 |
| 29.6 | rhino | a_rhino_land | self | legL / chest | 1-7 (7) worst 3 |
| 29.3 | rhino | a_rhino_land | self | legL / armL | 2-5 (4) worst 3 |
| 29.2 | kat | a_fall_special | self | legR / handR | 0-48 (49) worst 24 |
| 28.9 | bigbill | a_bigbill_escape_b | self | handR / head | 2-46 (45) worst 40 |
| 28.9 | bigbill | a_bigbill_escape_f | self | handR / head | 2-46 (45) worst 40 |
| 28.7 | vic | a_special_guard | self | handR / head | 0-10 (11) worst 2 |
| 28.6 | bigbill | a_special_charge | self | handR / head | 0-8 (9) worst 1 |
| 28.5 | bigbill | a_bigbill_fthrow | self | handR / head | 1-15 (15) worst 4 |
| 28.4 | bigbill | a_bigbill_bthrow | self | elbowR / head | 19-25 (7) worst 23 |
