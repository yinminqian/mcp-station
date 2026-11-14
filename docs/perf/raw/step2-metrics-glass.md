<!-- step1-glass round 1: 16 switches; first: 421 271 237 231 258 320 245 239 376 305 325 258 348 360 228 346 -->
<!-- step1-glass round 2: 16 switches; first: 603 284 310 196 312 342 330 248 191 227 316 210 237 413 411 364 -->
<!-- step1-glass round 3: 16 switches; first: 395 267 231 242 253 327 231 318 222 233 338 245 253 203 229 348 -->
<!-- step1-glass round 4: 16 switches; first: 422 255 215 213 266 369 900 364 418 451 430 274 300 402 408 541 -->
<!-- step2-glass round 1: 16 switches; first: 373 247 495 209 122 248 146 203 180 222 183 154 205 170 153 196 -->
<!-- step2-glass round 2: 16 switches; first: 365 205 309 217 196 199 170 156 190 149 239 151 184 200 149 232 -->
<!-- step2-glass round 3: 16 switches; first: 388 269 270 249 130 162 145 185 203 156 209 173 172 187 138 178 -->
<!-- step2-glass round 4: 16 switches; first: 397 249 391 282 133 224 148 256 137 208 191 155 133 161 169 226 -->

## 首段阻塞(ms,中位数)

| 页面 | step1-glass 首次 | step1-glass 再次 | step2-glass 首次 | step2-glass 再次 |
|---|---:|---:|---:|---:|
| mcps | 421 | 332 | 380 | 204 |
| services | 269 | 252 | 248 | 152 |
| calls | 234 | 277 | 350 | 185 |
| overview | — | 262 | — | 151 |
| settings | 222 | 368 | 233 | 183 |

## 合并忙区间(间隔<5ms)(ms,中位数)

| 页面 | step1-glass 首次 | step1-glass 再次 | step2-glass 首次 | step2-glass 再次 |
|---|---:|---:|---:|---:|
| mcps | 500 | 389 | 490 | 221 |
| services | 291 | 274 | 304 | 170 |
| calls | 287 | 335 | 411 | 207 |
| overview | — | 302 | — | 151 |
| settings | 249 | 380 | 262 | 188 |

## 超帧累计(ms,中位数)

| 页面 | step1-glass 首次 | step1-glass 再次 | step2-glass 首次 | step2-glass 再次 |
|---|---:|---:|---:|---:|
| mcps | 479 | 371 | 440 | 234 |
| services | 282 | 251 | 296 | 154 |
| calls | 286 | 345 | 379 | 188 |
| overview | — | 279 | — | 175 |
| settings | 229 | 361 | 258 | 202 |

## 首段之后最长单段(ms,中位数)

| 页面 | step1-glass 首次 | step1-glass 再次 | step2-glass 首次 | step2-glass 再次 |
|---|---:|---:|---:|---:|
| mcps | 71 | 55 | 74 | 9 |
| services | 31 | 9 | 41 | 8 |
| calls | 51 | 53 | 25 | 18 |
| overview | — | 12 | — | 16 |
| settings | 29 | 10 | 41 | 23 |

## 逐次数值(首段阻塞 / 超帧累计)

- mcps step1-glass first: 421/472 603/595 395/453 422/486
- mcps step1-glass again: 320/356 325/363 342/386 316/354 327/361 338/380 369/405 430/471
- mcps step2-glass first: 373/427 365/427 388/476 397/453
- mcps step2-glass again: 248/240 183/175 199/237 239/230 162/155 209/201 224/420 191/261
- services step1-glass first: 271/289 284/296 267/260 255/275
- services step1-glass again: 245/252 258/250 330/346 210/219 231/222 245/238 900/892 274/266
- services step2-glass first: 247/246 205/291 269/301 249/301
- services step2-glass again: 146/218 154/145 170/161 151/143 145/197 173/212 148/140 155/147
- calls step1-glass first: 237/273 310/344 231/298 215/252
- calls step1-glass again: 239/261 348/412 248/295 237/375 318/354 253/290 364/446 300/335
- calls step2-glass first: 495/487 309/303 270/293 391/454
- calls step2-glass again: 203/219 205/199 156/156 184/231 185/177 172/164 256/260 133/135
- overview step1-glass again: 258/250 305/297 228/258 312/304 227/227 411/451 253/261 233/303 229/220 266/257 451/442 408/460
- overview step2-glass again: 122/118 222/310 153/146 196/188 149/239 149/141 130/128 156/247 138/145 133/231 208/208 169/161
- settings step1-glass first: 231/245 196/220 242/233 213/225
- settings step1-glass again: 376/368 360/354 191/203 413/415 222/215 203/194 418/410 402/412
- settings step2-glass first: 209/237 217/238 249/298 282/277
- settings step2-glass again: 180/171 170/233 190/246 200/192 203/212 187/214 137/149 161/153
