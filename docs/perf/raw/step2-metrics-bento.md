<!-- step1-bento round 1: 16 switches; first: 162 93 96 103 88 80 91 187 123 168 409 112 201 154 88 76 -->
<!-- step1-bento round 2: 16 switches; first: 162 123 67 58 68 124 67 66 69 64 73 63 95 47 113 111 -->
<!-- step1-bento round 3: 16 switches; first: 116 80 62 112 101 75 185 60 57 78 74 82 77 60 92 69 -->
<!-- step1-bento round 4: 16 switches; first: 193 140 72 186 127 306 98 74 179 201 159 93 153 271 120 119 -->
<!-- step2-bento round 1: 16 switches; first: 160 125 90 94 10 14 29 15 8 15 15 8 22 19 13 19 -->
<!-- step2-bento round 2: 16 switches; first: 176 84 87 132 29 7 8 12 7 12 14 7 7 13 45 19 -->
<!-- step2-bento round 3: 16 switches; first: 156 114 88 67 21 6 7 21 25 12 16 24 9 27 15 7 -->
<!-- step2-bento round 4: 16 switches; first: 202 96 157 89 9 12 14 16 12 51 15 8 14 19 20 17 -->

## 首段阻塞(ms,中位数)

| 页面 | step1-bento 首次 | step1-bento 再次 | step2-bento 首次 | step2-bento 再次 |
|---|---:|---:|---:|---:|
| mcps | 162 | 102 | 168 | 14 |
| services | 108 | 92 | 105 | 8 |
| calls | 70 | 86 | 89 | 14 |
| overview | — | 97 | — | 15 |
| settings | 107 | 96 | 92 | 16 |

## 合并忙区间(间隔<5ms)(ms,中位数)

| 页面 | step1-bento 首次 | step1-bento 再次 | step2-bento 首次 | step2-bento 再次 |
|---|---:|---:|---:|---:|
| mcps | 801 | 495 | 223 | 45 |
| services | 393 | 410 | 148 | 80 |
| calls | 370 | 436 | 137 | 41 |
| overview | — | 460 | — | 63 |
| settings | 419 | 459 | 249 | 157 |

## 超帧累计(ms,中位数)

| 页面 | step1-bento 首次 | step1-bento 再次 | step2-bento 首次 | step2-bento 再次 |
|---|---:|---:|---:|---:|
| mcps | 214 | 243 | 161 | 28 |
| services | 183 | 280 | 122 | 27 |
| calls | 211 | 206 | 105 | 28 |
| overview | — | 202 | — | 32 |
| settings | 213 | 228 | 95 | 14 |

## 首段之后最长单段(ms,中位数)

| 页面 | step1-bento 首次 | step1-bento 再次 | step2-bento 首次 | step2-bento 再次 |
|---|---:|---:|---:|---:|
| mcps | 32 | 42 | 10 | 19 |
| services | 54 | 54 | 29 | 26 |
| calls | 46 | 34 | 30 | 23 |
| overview | — | 32 | — | 17 |
| settings | 36 | 29 | 18 | 13 |

## 逐次数值(首段阻塞 / 超帧累计)

- mcps step1-bento first: 162/309 162/219 116/152 193/209
- mcps step1-bento again: 80/228 409/440 124/258 73/143 75/121 74/154 306/414 159/386
- mcps step2-bento first: 160/152 176/168 156/153 202/260
- mcps step2-bento again: 14/31 15/24 7/8 14/7 6/7 16/56 12/68 15/68
- services step1-bento first: 93/167 123/182 80/185 140/269
- services step1-bento again: 91/290 112/307 67/117 63/138 185/285 82/226 98/278 93/281
- services step2-bento first: 125/148 84/99 114/134 96/111
- services step2-bento again: 29/52 8/0 8/50 7/0 7/23 24/65 14/29 8/26
- calls step1-bento first: 96/324 67/154 62/156 72/267
- calls step1-bento again: 187/404 201/337 66/121 95/139 60/94 77/156 74/267 153/255
- calls step2-bento first: 90/104 87/100 88/105 157/219
- calls step2-bento again: 15/40 22/72 12/3 7/2 21/17 9/20 16/35 14/59
- overview step1-bento again: 88/282 168/318 88/182 68/177 64/162 113/170 101/198 78/192 92/207 127/337 201/321 120/368
- overview step2-bento again: 10/35 15/41 13/28 29/53 12/16 45/289 21/16 12/141 15/23 9/4 51/58 20/14
- settings step1-bento first: 103/310 58/102 112/115 186/338
- settings step1-bento again: 123/448 154/288 69/166 47/143 57/168 60/102 179/292 271/379
- settings step2-bento first: 94/92 132/333 67/73 89/98
- settings step2-bento again: 8/1 19/12 7/1 13/5 25/30 27/26 12/16 19/51
