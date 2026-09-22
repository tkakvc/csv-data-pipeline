# 【このファイルの役割】variables.tfで「defaultが無い」と宣言した変数に、実際の値を渡す場所。
# variables.tfが「引数の宣言」なら、こちらは「実際に渡す引数の値」に相当する。
#
# 今は全ての変数にdefaultがあるため空。defaultの無い変数を追加した場合、
# ここに書かないとterraform planが値を聞いてくる。
