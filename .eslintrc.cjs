module.exports = {
  root: true,
  env: {
    node: true,
    es2022: true,
    browser: true
  },
	// Nötige devDependencies: npm install -D @typescript-eslint/parser @typescript-eslint/eslint-plugin
  // TypeScript parser und plugin aktivieren
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: 'module',
    // Typ-basierte Regeln, entkommentieren:
    // project: ['./tsconfig.json', './tsconfig.server.json'],
    // tsconfigRootDir: __dirname
  },

  plugins: ['@typescript-eslint'],

  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'prettier'
  ],

  rules: {
    'no-console': 'off'
  },

  ignorePatterns: ['dist', 'node_modules']
};
