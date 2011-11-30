require 'drb/drb'
require 'yaml'

require 'cli/mrkmctl_options'
require 'cli/murakumo_options'
require 'misc/murakumo_const'

# オプションをパース
options = mrkmctl_parse_args

# リモートオブジェクトを生成
there = DRbObject.new_with_uri("drbunix:#{options[:socket]}")

cmd, arg = options[:command]

# 各コマンドの処理
begin
  case cmd
  # 一覧表示
  when :list
    # レコードの取得
    records = there.list_records

    # 値の書き換え
    records.each do |r|
      priority = case r[3]
                 when Murakumo::ORIGIN
                   'Origin'
                 when Murakumo::MASTER
                   'Master'
                 when Murakumo::SECONDARY
                   'Secondary'
                 else
                   'Backup'
                 end

      r[3] = priority
      r[4] = (r[4] == Murakumo::ACTIVE ? 'Active' : 'Inactive')
    end

    if arg.kind_of?(String)
      # 引数がある場合はフィルタリング（TTLを除く）
      records = records.select {|r| r.values_at(0, 1, 3, 4).any?{|i| i.to_s =~ /\A#{arg.to_s}/i } }
    end

    if records.empty?
      puts 'No macth'
    else
      puts <<-EOF
IP address       TTL     Priority   Activity  Hostname
---------------  ------  ---------  --------  ----------
      EOF
      records.each do |r|
        puts '%-15s  %6d  %-9s  %-8s  %s' % r.values_at(0, 2, 3, 4, 1)
      end
    end

  # レコードの追加・更新
  when :add
    is_success, errmsg = there.add_or_rplace_records(arg)
    is_success or raise(errmsg)

  # レコードの削除
  when :delete
    is_success, errmsg = there.delete_records(arg)
    is_success or raise(errmsg)

  # ノードの追加
  when :add_node
    is_success, errmsg = there.add_nodes(arg)
    is_success or raise(errmsg)

  # ノードの削除
  when :delete_node
    is_success, errmsg = there.delete_nodes(arg)
    is_success or raise(errmsg)

  # 属性の取得
  when :get
    puts "#{arg}=#{there.get_attr(arg)}"

  # 属性の設定
  when :set
    is_success, errmsg = there.set_attr(*arg)
    is_success or raise(errmsg)

  # デッドリストのクリア
  when :clear_dead_list
    n = there.clear_dead_list
    puts "#{n} nodes were deleted"

  # 設定のテスト
  when :configtest
    conf = arg.kind_of?(String) ? arg : '/etc/murakumo.yml' 
    ARGV.clear
    ARGV.concat(['-c', conf])
    murakumo_parse_args
    puts 'Syntax OK'

  # 設定の出力
  when :yaml
    puts there.to_hash.to_yaml

  end
rescue => e
  $stderr.puts "error: #{e.message}"
  exit 1
end
