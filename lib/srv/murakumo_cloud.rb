require 'forwardable'
require 'rgossip2'
require 'sqlite3'

module Murakumo
  extend Forwardable

  class Cloud

    def initialize(options)
      # リソースレコードからアドレスとデータを取り出す
      data = options[:record]
      address = data.shift

      # データベースを作成してレコードを更新
      create_database
      update(address, data)

      # ゴシップオブジェクトを生成
      @gossip = RGossip2.client({
        :initial_nodes   => options[:initial_nodes],
        :address         => address,
        :data            => data,
        :auth_key        => options[:auth_key],
        :port            => options[:gossip_port],
        :node_lifetime   => options[:gossip_node_lifetime],
        :gossip_interval => options[:gossip_send_interval],
        :receive_timeout => options[:gossip_receive_timeout],
        :logger          => options[:logger],
      })

      # ノードの更新をフック
      @gossip.context.callback_handler = lambda do |action, address, timestamp, data|
        case action
        when :add, :comeback
          update(address, data)
        when :delete
          delete(address)
        end
      end

      # XXX: ヘルスチェックの実装
    end

    # Control of service
    def_delegators :@gossip, :start, :stop

    def close
      # データベースをクローズ
      @db.close
    end

    # Operation of storage 

    def update(address, data)
      name, ttl, weight, priority = data
      priority = (priority == :MASTER) ? 1 : 0
      activity = 1 # Active

      @db.execute(<<-EOS, address, name, ttl, weight, priority, activity)
        REPLACE INTO record (ip_address, name, ttl, weight, priority, activity)
        VALUES (?, ?, ?, ?, ?, ?)
      EOS
    end

    delete(address)
      @db.execute('DELETE FROM record WHERE ip_address = ?', address)
    end

    # Search of records

    def address_exist?(name)
      @db.get_first_row(<<-EOS, name, 1).first.nonzero?
        SELECT COUNT(*) FROM records WHERE name = ? AND activity = ?
      EOS
    end

    def lookup_addresses(name)
      records = []

      sql = <<-EOS
        SELECT ip_address, ttl, weight FROM records
        WHERE name = ? AND priority = ? AND activity = ?
      EOS

      # 優先度の高いアクティブなレコードを検索
      @db.execute(sql, name, 1, 1).each {|i| records << i }

      # レコードが見つからなかった場合は優先度の低いレコードを検索
      @db.execute(sql, name, 0, 1).each {|i| records << i } if records.empty?

      return records
    end

    def name_exist?(address)
      address = x_ip_addr(address)

      @db.get_first_row(<<-EOS, address, 1).first.nonzero?
        SELECT COUNT(*) FROM records WHERE ip_address = ? AND activity = ?
      EOS
    end

    def lookup_name(address)
      address = x_ip_addr(address)
      record = nil

      sql = <<-EOS
        SELECT name, ttl, weight FROM records
        WHERE ip_address = ? AND priority = ? AND activity = ? LIMIT 1
      EOS

      # 優先度の高いアクティブなレコードを検索
      record = @db.get_first_row(sql, address, 1, 1)

      # レコードが見つからなかった場合は優先度の低いレコードを検索
      record = @db.get_first_row(sql, address, 0, 1) unless record

      return record
    end

    private

    # リソースレコードのデータベース作成
    # もう少し並列処理に強いストレージに変えたいが…
    def create_database
      @db = SQLite3::Database.new(':memory:')

      # リソースレコード用のテーブル
      # （Typeは必要？）
      @db.execute(<<-EOS)
        CREATE TABLE records (
          ip_address INTEGER PRIMARY KEY,
          , name     TEXT NOT NULL
          , ttl      INTEGER NOT NULL
          , weight   INTEGER NOT NULL
          , priority INTEGER NOT NULL /* MASTER:1, BACKUP:0 */
          , activity INTEGER NOT NULL /* Active:1, Inactive:0 */
        )
      EOS

      # インデックスを作成（必要？）
      @db.execute(<<-EOS)
        CREATE INDEX idx_name_prio_act
        ON records (name, priority, activity)
      EOS

      @db.execute(<<-EOS)
        CREATE INDEX idx_name_act
        ON records (name, activity)
      EOS

      @db.execute(<<-EOS)
        CREATE INDEX idx_ip_prio_act
        ON records (ip_address, priority, activity)
      EOS

      @db.execute(<<-EOS)
        CREATE INDEX idx_ip_act
        ON records (ip_address, activity)
      EOS
    end

    # 逆引き名の変換
    def x_ip_addr(name)
      name.sub(/\.in-addr\.arpa\Z/, '').split('.').reverse.join('.')
    end

  end # Cloud

end # Murakumo
