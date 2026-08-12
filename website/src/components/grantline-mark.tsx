export default function GrantlineMark({
  className,
  ...props
}: React.SVGProps<SVGSVGElement>) {
  return (
    <svg
      viewBox="0 0 28 28"
      aria-hidden="true"
      focusable="false"
      className={className}
      {...props}
    >
      <rect
        x="0.75"
        y="0.75"
        width="26.5"
        height="26.5"
        rx="2.75"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
      />
      <path
        d="M17.2 9.2c-.8-1.35-2.05-2.05-3.55-2.05-2.9 0-4.75 2.55-4.75 6.6 0 4.05 1.75 6.35 4.55 6.35 1.65 0 2.95-.65 3.8-1.85v-3.6h-3.65"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.45"
        strokeLinecap="square"
        strokeLinejoin="miter"
      />
      <path
        d="M17.7 6.6 11.8 22.3"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.65"
        strokeLinecap="square"
        opacity=".92"
      />
    </svg>
  );
}
