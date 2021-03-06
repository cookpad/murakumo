require 'cli/murakumo_options'
require 'srv/murakumo_server'

# オプションをパース
options = murakumo_parse_args

# サーバの初期化
Murakumo::Server.init(options)

if options[:daemon]
  # デーモン化する場合
  # RExecに処理を委譲するのでARGVの先頭にdaemonizeのコマンドを格納
  ARGV.unshift options[:daemon].to_s

  Murakumo::Server.working_directory = options[:working_dir]
  Murakumo::Server.daemonize
else
  # デーモン化しない場合
  Murakumo::Server.run
end
