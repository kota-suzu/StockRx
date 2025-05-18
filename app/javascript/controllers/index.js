// このファイルは自動生成されます
// Stimulusコントローラーのエントリーポイントとして機能し、自動的にコントローラーを探索・登録します

import { application } from "./application"

// すべてのコントローラーをインポートし登録する
import ImportProgressController from "./import_progress_controller"
application.register("import-progress", ImportProgressController)

// 将来的に追加するコントローラーがあれば以下に追加：
// import ExampleController from "./example_controller"
// application.register("example", ExampleController) 