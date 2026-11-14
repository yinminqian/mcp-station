<!-- step1-glass round 1: 16 switches; first: 365 285 270 238 225 497 305 289 187 226 320 228 235 238 247 327 -->
<!-- step1-glass round 2: 16 switches; first: 459 209 229 248 269 298 247 254 228 261 312 259 235 194 226 399 -->
<!-- step1-glass round 3: 16 switches; first: 372 273 249 266 235 310 238 218 183 233 311 299 251 206 229 364 -->
<!-- step2-glass round 1: 16 switches; first: 339 258 272 238 131 155 183 173 146 169 174 169 197 161 747 235 -->
<!-- step2-glass round 2: 16 switches; first: 315 247 311 212 120 171 160 191 151 157 190 138 174 196 148 234 -->
<!-- step2-glass round 3: 16 switches; first: 334 255 269 249 129 184 166 140 153 167 168 149 181 126 138 180 -->
<!-- step3-glass round 1: 16 switches; first: 475 255 362 171 154 201 148 162 115 131 231 97 270 125 135 222 -->
<!-- step3-glass round 2: 16 switches; first: 397 179 238 171 105 193 105 242 120 133 226 150 172 170 158 200 -->
<!-- step3-glass round 3: 16 switches; first: 360 196 236 185 130 244 134 254 102 132 207 156 253 155 149 184 -->

## 首段阻塞(ms,中位数)

| 页面 | step1-glass 首次 | step1-glass 再次 | step2-glass 首次 | step2-glass 再次 | step3-glass 首次 | step3-glass 再次 |
|---|---:|---:|---:|---:|---:|---:|
| mcps | 372 | 311 | 334 | 173 | 397 | 217 |
| services | 273 | 253 | 255 | 163 | 196 | 141 |
| calls | 249 | 243 | 272 | 177 | 238 | 247 |
| overview | — | 233 | — | 148 | — | 133 |
| settings | 248 | 200 | 238 | 152 | 171 | 122 |

## 合并忙区间(间隔<5ms)(ms,中位数)

| 页面 | step1-glass 首次 | step1-glass 再次 | step2-glass 首次 | step2-glass 再次 | step3-glass 首次 | step3-glass 再次 |
|---|---:|---:|---:|---:|---:|---:|
| mcps | 457 | 368 | 425 | 176 | 499 | 233 |
| services | 282 | 258 | 274 | 171 | 224 | 151 |
| calls | 302 | 285 | 320 | 196 | 329 | 267 |
| overview | — | 256 | — | 149 | — | 165 |
| settings | 248 | 230 | 266 | 157 | 200 | 131 |

## 超帧累计(ms,中位数)

| 页面 | step1-glass 首次 | step1-glass 再次 | step2-glass 首次 | step2-glass 再次 | step3-glass 首次 | step3-glass 再次 |
|---|---:|---:|---:|---:|---:|---:|
| mcps | 437 | 345 | 397 | 176 | 446 | 218 |
| services | 264 | 245 | 257 | 166 | 201 | 135 |
| calls | 274 | 263 | 297 | 205 | 296 | 250 |
| overview | — | 239 | — | 149 | — | 148 |
| settings | 239 | 209 | 278 | 183 | 215 | 129 |

## 首段之后最长单段(ms,中位数)

| 页面 | step1-glass 首次 | step1-glass 再次 | step2-glass 首次 | step2-glass 再次 | step3-glass 首次 | step3-glass 再次 |
|---|---:|---:|---:|---:|---:|---:|
| mcps | 75 | 47 | 77 | 13 | 45 | 15 |
| services | 11 | 6 | 17 | 9 | 22 | 11 |
| calls | 41 | 43 | 8 | 18 | 33 | 42 |
| overview | — | 8 | — | 9 | — | 16 |
| settings | 7 | 21 | 55 | 28 | 25 | 25 |

## 逐次数值(首段阻塞 / 超帧累计)

- mcps step1-glass first: 365/437 459/450 372/430
- mcps step1-glass again: 497/489 320/352 298/327 312/347 310/343 311/342
- mcps step2-glass first: 339/408 315/392 334/397
- mcps step2-glass again: 155/147 174/165 171/230 190/182 184/242 168/170
- mcps step3-glass first: 475/467 397/446 360/394
- mcps step3-glass again: 201/200 231/228 193/208 226/233 244/239 207/202
- services step1-glass first: 285/280 209/222 273/264
- services step1-glass again: 305/297 228/223 247/239 259/251 238/230 299/291
- services step2-glass first: 258/257 247/285 255/256
- services step2-glass again: 183/175 169/227 160/152 138/130 166/158 149/187
- services step3-glass first: 255/265 179/184 196/201
- services step3-glass again: 148/142 97/97 105/99 150/144 134/127 156/175
- calls step1-glass first: 270/303 229/252 249/274
- calls step1-glass again: 289/318 235/280 254/246 235/227 218/242 251/309
- calls step2-glass first: 272/263 311/303 269/297
- calls step2-glass again: 173/164 197/189 191/221 174/283 140/244 181/173
- calls step3-glass first: 362/378 238/247 236/296
- calls step3-glass again: 162/211 270/314 242/246 172/207 254/254 253/294
- overview step1-glass again: 225/244 226/217 247/239 269/276 261/253 226/245 235/226 233/232 229/220
- overview step2-glass again: 131/127 169/284 747/739 120/122 157/149 148/159 129/120 167/159 138/130
- overview step3-glass again: 154/153 131/166 135/136 105/103 133/159 158/155 130/129 132/131 149/148
- settings step1-glass first: 238/230 248/239 266/257
- settings step1-glass again: 187/208 238/230 228/220 194/199 183/189 206/210
- settings step2-glass first: 238/237 212/278 249/299
- settings step2-glass again: 146/143 161/214 151/198 196/188 153/150 126/179
- settings step3-glass first: 171/171 171/215 185/216
- settings step3-glass again: 115/110 125/147 120/111 170/207 102/98 155/196
