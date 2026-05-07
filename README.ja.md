# DDW — Decision-Driven Workflow

**ドリフトしないコードを書こう。
決定なしにコードなし。タスクなしに実装なし。**

> 悪い開発を「直す」んじゃなくて、「起きなくする」仕組み。

DDWはPMツールじゃないよ。
**開発の品質をシステムレベルで守るハーネス**だと思ってほしい。

---

## 何ができるの？

- **ダメなコードをそもそも書かせない**
  決定 → タスク → コード。ショートカットなし。

- **すべての変更が証明できる**
  小さいタスクに厳密な受入基準がついてる。

- **ルールはお願いじゃなくて強制**
  フックがルール違反をブロック。プロンプトで回避？無理。

- **仕様とコードがずっと同期**
  ドリフト検出が自動で矛盾を見つけてくれる。

- **開発がシステムになる**
  決定、タスク、QA、振り返り — 全部記録されて、全部つながってる。

---

## フロー

決定 → タスク → 実装 → QA → インテグレーション → クローズ

フルパワーだとこう：

```
/ddw:ideate → /ddw:decision → /ddw:task → /ddw:sendit → /ddw:review
                                              ↓
                                  ready_for_integration（統合待ち）
                                              ↓
                                  ddw-queue tick → ddw-stage
                                              ↓
                                          /ddw:close
                                              ↓
                                       /ddw:prd close
```

---

## なんで必要なの？

チームが失敗するのって、コード書けないからじゃないんだよね。
だいたいこういう理由：

- 決定があいまい
- タスクが不明確
- QAがバラバラ
- 仕様とコードがズレてる

DDWはこれを全部直す — **間違ったやり方ができないようにして。**

---

## 強制の仕組み

2つのレイヤー：

- **ソフト** — AIへのガイダンス（`CLAUDE.md`）
- **ハード** — 物理的に不正な操作をブロックするシェルフック

ルール破ったら？ **動かない。それだけ。**

---

## 立ち位置

- PMツールは作業を管理する
- CIツールはコードをテストする
- **DDWは開発の「やり方」を強制する**

---

## インストール

```json
// .claude/settings.json
{
  "plugins": [
    { "path": "/path/to/ddw" }
  ]
}
```

あとは `/ddw:init` を実行するだけ。

---

## コマンド

| コマンド | やること |
|---|---|
| `/ddw:init` | プロジェクトにDDWを導入 |
| `/ddw:ideate` | アイデアをPRDに整える |
| `/ddw:decision` | アーキテクトレビュー付きの決定を作る |
| `/ddw:prd close PRD-id` | 関連する決定が揃ったらPRDをクローズ |
| `/ddw:task` | 決定をスコープ付きタスクに分ける |
| `/ddw:sendit` | 実装スタート。レビュー通ったらインテグレーション待ち行列へ |
| `/ddw:qa` | 自動QA：受入基準＋不変条件チェック |
| `/ddw:review` | QA＋テスト＋オーナーチェックリスト |
| `/ddw:close` | 仕様更新、ドリフトチェック、振り返り、アーカイブ、キュー進行 |
| `/ddw:drift` | 仕様とコードの整合性チェック |
| `/ddw:architect` | 設計レビュー or ガードレール初期設定 |
| `/ddw:upgrade` | 最新バージョンにアップグレード |

### インテグレーションスクリプト（プロジェクトルートで実行）

| スクリプト | 用途 |
|---|---|
| `bash $CLAUDE_PLUGIN_DIR/scripts/setup-worktree.sh TASK-id` | タスクごとのworktreeを作成 |
| `bash $CLAUDE_PLUGIN_DIR/scripts/ddw-queue tick \| list \| status` | インテグレーションFIFOを管理 |
| `bash $CLAUDE_PLUGIN_DIR/scripts/ddw-stage TASK-id` | 準備完了タスクをintegration worktreeにマージ |
| `bash $CLAUDE_PLUGIN_DIR/scripts/ddw-unstage TASK-id` | クリーンに巻き戻し |
| `bash $CLAUDE_PLUGIN_DIR/scripts/ddw-integration-reset --yes` | integration worktreeをorigin/mainにリセット |
| `node $CLAUDE_PLUGIN_DIR/scripts/ddw-index.mjs --root .` | 4つのログビューを再生成 |

---

## AI開発TIPS

- **タスク終わったら `/clear` しよう**
  コンテキスト溜まると遅くなるよ。リセットしたほうが早い。

- **複数タスク同時にやりたい？ ビルトインのworktreeヘルパー使おう**
  `bash $CLAUDE_PLUGIN_DIR/scripts/setup-worktree.sh TASK-id` で隔離されたworktreeが立ち上がるよ。ポートの自動オフセット（`.env.ddw`）、シークレットのシンボリックリンク、`task/TASK-id` ブランチも全部セットで。`ddw.json` の `maxConcurrent` で同時実行数の上限を設定できる。

- **Gitはまだ連携しなくていい**
  手動で十分。面倒になったらAIにやらせればいい。

- **迷ったら「next?」って聞くだけ**
  DDWがパイプライン見て、次やること教えてくれる。

- **AIが確認求めてきたら？**
  ちゃんと確認して「OK」「確認した」で進めよう。（ちゃんと見てね）

- **英語で始まっても大丈夫**
  「日本語で進めて」って言えば切り替わるよ。ドキュメントも日本語いける。

---

## ドキュメント

- [詳細ガイド](GUIDE.md) — ワークフロー全体のリファレンス、フック図、エージェントプロファイル

## ライセンス

[MIT](LICENSE)
