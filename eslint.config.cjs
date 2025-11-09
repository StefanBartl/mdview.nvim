const { defineConfig, globalIgnores } = require('eslint/config');

const globals = require('globals');
const tsParser = require('@typescript-eslint/parser');
const typescriptEslint = require('@typescript-eslint/eslint-plugin');
const js = require('@eslint/js');

const { FlatCompat } = require('@eslint/eslintrc');

const compat = new FlatCompat({
  baseDirectory: __dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all,
});

module.exports = defineConfig([
  {
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.browser,
      },
      // Nötige devDependencies: npm install -D @typescript-eslint/parser @typescript-eslint/eslint-plugin
      // TypeScript parser und plugin aktivieren

      parser: tsParser,
      ecmaVersion: 2022,
      sourceType: 'module',
      parserOptions: {},
      // Typ-basierte Regeln, entkommentieren:
      // project: ['./tsconfig.json', './tsconfig.server.json'],
      // tsconfigRootDir: __dirname
    },

    plugins: {
      '@typescript-eslint': typescriptEslint,
    },

    extends: compat.extends(
      'eslint:recommended',
      'plugin:@typescript-eslint/recommended',
      'prettier',
    ),

    rules: {
      'no-console': 'off',
    },
  },
  globalIgnores(['**/dist', '**/node_modules']),
]);
