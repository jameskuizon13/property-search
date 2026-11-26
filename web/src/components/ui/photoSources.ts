/** The bundled demo photos come in two widths: `house-01.webp` (960 px) and `house-01-480.webp`. */
const DEMO_PHOTO = /^(\/images\/properties\/[a-z]+-\d+)\.webp$/

/** Both widths for `srcset`, or undefined for any other photo (a future upload gets a plain `src`). */
export function srcSetFor(src: string) {
  const base = DEMO_PHOTO.exec(src)?.[1]
  return base && `${base}-480.webp 480w, ${src} 960w`
}

/** The 480 px copy for thumbnails, or the photo itself when there is none. */
export function smallPhoto(src: string) {
  const base = DEMO_PHOTO.exec(src)?.[1]
  return base ? `${base}-480.webp` : src
}
