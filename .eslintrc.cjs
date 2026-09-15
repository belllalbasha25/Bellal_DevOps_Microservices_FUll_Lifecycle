module.exports = {
  env: {
    node: true,
    es2021: true,
    jest: true
  },
  extends: [
    "eslint:recommended"
  ],
  parserOptions: {
    ecmaVersion: "latest",
    sourceType: "commonjs"
  },
  rules: {
    "no-unused-vars": "warn",
    "no-undef": "error"
  }
};
