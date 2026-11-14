<!-- step1-bento round 1: 16 switches; first: 167 92 71 76 103 85 100 115 71 78 100 117 100 78 72 122 -->
<!-- step1-bento round 2: 16 switches; first: 174 151 70 69 84 98 73 65 63 84 72 76 90 58 78 72 -->
<!-- step1-bento round 3: 16 switches; first: 160 127 72 108 75 72 63 84 77 94 76 66 83 75 79 82 -->
<!-- step2-bento round 1: 16 switches; first: 168 120 68 80 15 25 707 66 8 64 19 48 19 8 22 8 -->
<!-- step2-bento round 2: 16 switches; first: 167 84 63 59 8 18 14 10 18 7 16 14 21 12 6 17 -->
<!-- step2-bento round 3: 16 switches; first: 489 129 89 93 13 19 9 18 14 14 22 8 16 6 11 18 -->
<!-- step3-bento round 1: 16 switches; first: 195 145 114 79 36 50 21 35 17 33 29 36 40 16 31 29 -->
<!-- step3-bento round 2: 16 switches; first: 179 121 67 55 31 28 60 45 40 40 38 30 42 37 38 55 -->
<!-- step3-bento round 3: 16 switches; first: 177 146 88 87 35 68 28 41 35 46 25 83 22 33 48 33 -->

## 首段阻塞(ms,中位数)

| 页面 | step1-bento 首次 | step1-bento 再次 | step2-bento 首次 | step2-bento 再次 | step3-bento 首次 | step3-bento 再次 |
|---|---:|---:|---:|---:|---:|---:|
| mcps | 167 | 81 | 168 | 19 | 179 | 33 |
| services | 127 | 74 | 120 | 14 | 145 | 33 |
| calls | 71 | 87 | 68 | 18 | 88 | 41 |
| overview | — | 79 | — | 13 | — | 36 |
| settings | 76 | 73 | 80 | 10 | 79 | 34 |

## 合并忙区间(间隔<5ms)(ms,中位数)

| 页面 | step1-bento 首次 | step1-bento 再次 | step2-bento 首次 | step2-bento 再次 | step3-bento 首次 | step3-bento 再次 |
|---|---:|---:|---:|---:|---:|---:|
| mcps | 429 | 425 | 178 | 74 | 189 | 65 |
| services | 398 | 365 | 155 | 110 | 157 | 54 |
| calls | 378 | 369 | 205 | 175 | 105 | 76 |
| overview | — | 484 | — | 45 | — | 62 |
| settings | 371 | 357 | 191 | 110 | 111 | 53 |

## 超帧累计(ms,中位数)

| 页面 | step1-bento 首次 | step1-bento 再次 | step2-bento 首次 | step2-bento 再次 | step3-bento 首次 | step3-bento 再次 |
|---|---:|---:|---:|---:|---:|---:|
| mcps | 237 | 142 | 171 | 51 | 182 | 49 |
| services | 194 | 167 | 118 | 59 | 153 | 88 |
| calls | 189 | 157 | 145 | 21 | 82 | 92 |
| overview | — | 174 | — | 45 | — | 64 |
| settings | 180 | 167 | 149 | 23 | 80 | 45 |

## 首段之后最长单段(ms,中位数)

| 页面 | step1-bento 首次 | step1-bento 再次 | step2-bento 首次 | step2-bento 再次 | step3-bento 首次 | step3-bento 再次 |
|---|---:|---:|---:|---:|---:|---:|
| mcps | 23 | 39 | 8 | 33 | 18 | 20 |
| services | 25 | 38 | 13 | 30 | 30 | 25 |
| calls | 39 | 31 | 35 | 15 | 10 | 31 |
| overview | — | 29 | — | 23 | — | 26 |
| settings | 32 | 25 | 50 | 19 | 21 | 18 |

## 逐次数值(首段阻塞 / 超帧累计)

- mcps step1-bento first: 167/251 174/166 160/237
- mcps step1-bento again: 85/233 100/228 98/161 72/104 72/124 76/111
- mcps step2-bento first: 168/159 167/171 489/480
- mcps step2-bento again: 25/64 19/11 18/15 16/38 19/102 22/70
- mcps step3-bento first: 195/187 179/181 177/182
- mcps step3-bento again: 50/56 29/44 28/25 38/44 68/75 25/53
- services step1-bento first: 92/194 151/192 127/207
- services step1-bento again: 100/171 117/192 73/162 76/108 63/148 66/189
- services step2-bento first: 120/118 84/98 129/126
- services step2-bento again: 707/698 48/290 14/12 14/27 9/49 8/69
- services step3-bento first: 145/200 121/138 146/153
- services step3-bento again: 21/90 36/99 60/87 30/35 28/58 83/94
- calls step1-bento first: 71/189 70/133 72/189
- calls step1-bento again: 115/156 100/158 65/145 90/163 84/156 83/163
- calls step2-bento first: 68/92 63/145 89/159
- calls step2-bento again: 66/204 19/21 10/12 21/88 18/16 16/22
- calls step3-bento first: 114/107 67/82 88/80
- calls step3-bento again: 35/179 40/137 45/62 42/96 41/88 22/68
- overview step1-bento again: 103/133 78/133 72/142 84/182 84/276 78/174 75/176 94/201 79/164
- overview step2-bento again: 15/18 64/114 22/78 8/0 7/3 6/1 13/54 14/45 11/63
- overview step3-bento again: 36/64 33/42 31/92 31/51 40/79 38/58 35/80 46/66 48/64
- settings step1-bento first: 76/170 69/181 108/180
- settings step1-bento again: 71/165 78/166 63/168 58/89 77/173 75/171
- settings step2-bento first: 80/176 59/98 93/149
- settings step2-bento again: 8/98 8/21 18/24 12/6 14/6 6/42
- settings step3-bento first: 79/92 55/59 87/80
- settings step3-bento again: 17/45 16/19 40/81 37/47 35/44 33/42
