# Body clash report (Collision Wrap) - with the Body Solve

Every clip each fighter plays, every frame, on its Collision Wrap (`data/wraps/<key>.collide.json`). A **self** clash is a
body part going into the fighter's own body deeper than it does at rest; a **floor** clash is a part under the floor in a
planted clip. Depths in cm at match height, tolerance 1.0 cm. Frames: first-last (how many).

Body Solve on: the largest correction on any bone was 92 degrees, the largest lift off the floor 118 cm.

| fighter | clips | with self clashes | with floor clashes | frames |
|---|---|---|---|---|
| vix | 83 | 14 | 7 | 2996 |
| carter | 83 | 39 | 5 | 3134 |
| goat | 83 | 2 | 2 | 3184 |
| slum | 83 | 5 | 0 | 3143 |
| al | 83 | 22 | 9 | 3188 |
| guru | 83 | 14 | 5 | 3034 |
| bigbill | 83 | 31 | 5 | 3101 |
| rhino | 83 | 19 | 6 | 3275 |
| hype | 83 | 33 | 6 | 3068 |
| vic | 83 | 47 | 4 | 3038 |
| kat | 83 | 60 | 21 | 3046 |
| **all** | **913** | **286** | **70** | **34207** |

## What clashes most

| parts | clips | worst cm |
|---|---|---|
| foot under the floor | 73 | 10.5 |
| elbow - head | 71 | 15.9 |
| arm - head | 67 | 17.7 |
| chest - elbow | 60 | 12.2 |
| hand - head | 51 | 20.5 |
| arm - torso | 40 | 17.1 |
| leg - torso | 39 | 10.5 |
| hand - leg | 35 | 15.2 |
| leg - tail | 35 | 9.3 |
| elbow - leg | 34 | 14.6 |
| arm - neck | 26 | 13.7 |
| chest - hips | 21 | 24.6 |
| ear - elbow | 21 | 11.9 |
| hand - hand | 19 | 10.7 |
| elbow - torso | 18 | 7.6 |
| foot - knee | 18 | 10.6 |
| ear - neck | 17 | 4.2 |
| knee - knee | 15 | 19.4 |
| foot - leg | 14 | 7.8 |
| ear - hand | 14 | 7.7 |
| ear - head | 14 | 5.1 |
| elbow - hand | 14 | 13.1 |
| foot - foot | 14 | 16.2 |
| tail under the floor | 14 | 22.8 |
| arm - leg | 13 | 11.5 |
| hand - torso | 11 | 9.5 |
| knee - tail | 9 | 11.6 |
| hand - knee | 9 | 7.4 |
| chest - fin | 8 | 15.5 |
| chest - head | 7 | 2.1 |

## Worst 60

| cm | fighter | clip | kind | parts | frames |
|---|---|---|---|---|---|
| 24.6 | rhino | a_rhino_land | self | hips / chest | 1-6 (6) worst 3 |
| 22.8 | al | a_al_dtilt | floor | tail3 | 7-13 (7) worst 7 |
| 20.5 | bigbill | a_bigbill_usmash | self | handR / head_3 | 31-44 (3) worst 43 |
| 20.3 | rhino | a_rhino_land | self | legL / chest | 2-4 (3) worst 3 |
| 19.4 | kat | w_walk | self | kneeL / kneeR | 17-54 (11) worst 51 |
| 17.9 | bigbill | a_item_tilt | self | handR / head_3 | 1-1 (1) worst 1 |
| 17.7 | kat | a_kat_usmash | self | armR / head | 11-33 (23) worst 12 |
| 17.7 | bigbill | a_bigbill_uair | self | handR / head_3 | 2-18 (16) worst 14 |
| 17.5 | bigbill | a_bigbill_special_rise | self | handR / head_3 | 4-35 (3) worst 4 |
| 17.4 | kat | a_special_rise | self | armR / head | 3-32 (30) worst 3 |
| 17.1 | vic | a_hammer | self | torso / armL | 13-22 (5) worst 14 |
| 16.6 | al | a_al_land | self | legL / chest | 2-4 (3) worst 3 |
| 16.2 | hype | w_walk | self | footL / footR | 17-55 (9) worst 53 |
| 16.1 | bigbill | a_bigbill_fair | self | handR / head_3 | 5-8 (4) worst 6 |
| 16.0 | al | a_al_land | self | legR / chest | 2-4 (3) worst 3 |
| 15.9 | vic | a_item_tilt | self | elbowR / head | 1-3 (3) worst 2 |
| 15.6 | kat | a_kat_bthrow | floor | handR | 24-24 (1) worst 24 |
| 15.5 | al | a_al_uair | self | chest / fin3 | 6-7 (2) worst 6 |
| 15.3 | kat | a_item_smash | self | armR / head | 1-24 (24) worst 21 |
| 15.2 | kat | a_kat_jab3 | self | armR / head | 3-11 (9) worst 3 |
| 15.2 | vic | a_pass | self | legL / handR | 4-11 (8) worst 6 |
| 14.7 | rhino | a_rhino_land | self | legR / chest | 2-4 (3) worst 3 |
| 14.6 | vix | a_vix_land | self | legR / elbowR | 2-3 (2) worst 2 |
| 14.6 | vic | a_item_tilt | self | handR / head | 1-3 (3) worst 2 |
| 14.4 | bigbill | a_bigbill_special_rise | self | handR / head_2 | 4-4 (1) worst 4 |
| 14.3 | bigbill | a_bigbill_uair | self | elbowR / head_2 | 1-18 (18) worst 15 |
| 14.3 | kat | w_run | self | footL / footR | 10-31 (3) worst 30 |
| 14.2 | bigbill | a_bigbill_damage_launch | self | handR / head_3 | 2-2 (1) worst 2 |
| 14.0 | kat | a_item_tilt | self | armR / head | 1-5 (5) worst 2 |
| 13.9 | goat | a_goat_damage_fall | self | elbowL / armR | 5-5 (1) worst 5 |
| 13.9 | kat | w_run | self | kneeL / kneeR | 10-31 (3) worst 30 |
| 13.8 | hype | w_walk | self | kneeL / kneeR | 17-54 (8) worst 52 |
| 13.8 | carter | w_walk | self | kneeL / kneeR | 14-18 (5) worst 18 |
| 13.7 | kat | w_walk | self | footL / footR | 17-53 (9) worst 51 |
| 13.7 | vic | a_special_rise | self | armR / neck | 3-5 (3) worst 3 |
| 13.5 | kat | a_kat_jab3 | self | legR / elbowR | 1-2 (2) worst 1 |
| 13.2 | carter | a_carter_fsmash | self | handR / head | 17-19 (3) worst 17 |
| 13.2 | vic | a_item_dash | self | torso / armR | 4-48 (6) worst 5 |
| 13.1 | vic | a_vic_usmash | self | elbowL / handR | 13-13 (1) worst 13 |
| 13.1 | kat | a_item_throw | self | armR / head | 1-4 (4) worst 2 |
| 13.1 | kat | a_kat_dash | self | legR / handR | 3-7 (5) worst 3 |
| 13.1 | vic | a_item_smash | self | armR / neck | 5-25 (13) worst 9 |
| 12.8 | bigbill | a_bigbill_utilt | self | handR / head_3 | 7-13 (7) worst 10 |
| 12.7 | al | a_al_uair | self | chest / fin2 | 6-17 (12) worst 6 |
| 12.5 | kat | a_kat_cliff_wait | self | armR / head | 0-48 (49) worst 0 |
| 12.5 | vic | w_walk | self | footL / footR | 18-53 (6) worst 52 |
| 12.2 | goat | a_goat_damage_fall | self | chest / elbowL | 3-6 (4) worst 5 |
| 12.2 | al | a_al_land | self | chest / elbowR | 1-6 (6) worst 3 |
| 12.1 | bigbill | a_bigbill_dash_attack | self | elbowR / head_2 | 6-12 (7) worst 10 |
| 12.1 | vix | a_vix_land | self | kneeL / elbowL | 2-4 (3) worst 3 |
| 12.0 | vic | w_walk | self | kneeL / kneeR | 18-52 (6) worst 51 |
| 11.9 | kat | a_special_rise | self | elbowR / earR3 | 3-5 (3) worst 3 |
| 11.9 | bigbill | a_bigbill_special_rise | self | handL / head | 4-4 (1) worst 4 |
| 11.8 | vic | a_item_tilt | self | torso / armR | 1-30 (8) worst 6 |
| 11.8 | vix | a_vix_land | floor | tail3 | 1-3 (3) worst 3 |
| 11.6 | al | a_special_punch | self | kneeR / tail2 | 43-43 (1) worst 43 |
| 11.5 | vic | a_special_rise | self | handR / head | 3-4 (2) worst 3 |
| 11.5 | guru | w_walk | self | kneeL / kneeR | 16-53 (8) worst 50 |
| 11.5 | vix | a_vix_land | self | legL / armL | 2-4 (3) worst 3 |
| 11.4 | hype | a_hype_dair | self | legR / handR | 18-19 (2) worst 19 |
