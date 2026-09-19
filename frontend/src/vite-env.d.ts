/// <reference types="vite/client" />

// 【AI任せでOK】GISが window.google として動的に生やす値を、TypeScriptに教えるためだけの宣言
export {}

declare global {
  interface Window {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- GISの型定義パッケージを入れるほどの規模ではないため、最小限の宣言に留める
    google: any
  }
}
