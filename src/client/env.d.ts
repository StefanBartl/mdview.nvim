// Vite treats a bare CSS import as a side-effect that injects the stylesheet;
// it has no meaningful JS export. Declare the module so tsc accepts the
// dynamic `import('./themes/*.css')` calls in main.ts.
declare module '*.css';
