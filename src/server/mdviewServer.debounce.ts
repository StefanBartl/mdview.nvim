// mdviewServer.debounce.ts
// English comments only in code as requested.

/**
 * Simple debounce implementation in TypeScript.
 * Suitable for server-side usage; avoids an external dependency.
 */

export function debounce<T extends (...args: any[]) => void>(
  fn: T,
  wait = 3000
): (...args: Parameters<T>) => void {
  let timer: NodeJS.Timeout | null = null;
  return function (...args: Parameters<T>) {
    if (timer) {
      clearTimeout(timer);
    }
    timer = setTimeout(() => {
      // call the original function with the latest arguments
      fn(...args);
      timer = null;
    }, wait);
  };
}
