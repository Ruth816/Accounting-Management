// ASPENCOM TECH INC logo (Ruth, 1 November): rising bars with a red arrow.
export function LogoMark({ size = 40 }: { size?: number }) {
  return (
    <svg viewBox="0 0 64 64" width={size} height={size} aria-hidden="true">
      <polygon points="13,30 21,27 21,56 13,56" fill="#43a047" />
      <polygon points="21,12 31,7 31,56 21,56" fill="#1f2a44" />
      <polygon points="31,16 40,12 40,56 31,56" fill="#1e88e5" />
      <polygon points="40,14 47,10 47,40 40,44" fill="#f39c12" />
      <path d="M5 48 C 20 54, 38 46, 46 24" fill="none" stroke="#e53935" strokeWidth="6" strokeLinecap="round" />
      <polygon points="38,22 55,10 52,30" fill="#e53935" />
    </svg>
  )
}

export const COMPANY = 'ASPENCOM TECH INC'
