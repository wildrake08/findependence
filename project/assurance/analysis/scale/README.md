# Scale check (UX-001 verification plan, WI-027)

`scale.exs` seeds a household with 10, 50, or 200 items and times page requests. Heights were
measured in headless Chromium: 1100 px wide for desktop, and in a 390 px frame for phone.

| Items | File | Home, server time | Item page | Home height, desktop | Home height, phone, before WI-027 | After |
|---|---|---|---|---|---|---|
| 10 | 13 KB | 1.7 ms | 1.7 ms | 2,155 px | 5,904 px | 4,534 px |
| 50 | 41 KB | 5.5 ms | 5.8 ms | 3,666 px | 12,052 px | 7,012 px |
| 200 | 144 KB | 20.8 ms | 18.1 ms | 9,334 px | 35,012 px | 16,360 px |

Times are the mean of 20 requests through the app's own handler on the development container, not
a household laptop; they include decrypting the member's view and the F-16 file fingerprint.
Desktop copes at 50 items. On phones each item used four labelled lines; WI-027 made items and
values two-line rows ("Rent · −$2,150.00 a month", then "Owned by you · Only the owners").
No table overflows its box at 390 px at any size.

Not addressed, and a question for STUDY-001: at 200 items the home page is still long on both
widths. Search, grouping, or paging would change what the home page is, so it is left for evidence.
