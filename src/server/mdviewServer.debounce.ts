// mdviewServer.debounce.ts
// English comments only in code as requested.

/**
 * Simple debounce implementation in TypeScript.
 * Suitable for server-side usage; avoids an external dependency.
 */

export function debounce<Args extends unknown[]>(
  fn: (...args: Args) => void,
  wait = 3000,
): (...args: Args) => void {
  // NodeJS.Timeout is the correct timer type for Node.js environments
  let timer: NodeJS.Timeout | null = null;
  return function (...args: Args) {
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
