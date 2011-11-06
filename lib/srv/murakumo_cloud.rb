require 'forwardable'
require 'rgossip2'
require 'sqlite3'

require 'misc/murakumo_const'

module Murakumo

  class Cloud
    extend Forwardable

    def initialize(options)
      # リソースレコードからアドレスとデータを取り出す
      data = options[:record]
      address = data.shift
      data[4] = ACTIVE # 最初はアクティブ

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
      @db.execute(<<-EOS, address, *data)
        REPLACE INTO records (ip_address, name, ttl, weight, priority, activity)
        VALUES (?, ?, ?, ?, ?, ?)
      EOS
    end

    def delete(address)
      @db.execute('DELETE FROM records WHERE ip_address = ?', address)
    end

    # Search of records

    def address_exist?(name)
      # シングルスレッドェ…
      @address_records = @db.execute(<<-EOS, name, ACTIVE)
        SELECT ip_address, ttl, weight, priority FROM records
        WHERE name = ? AND activity = ?
      EOS

      @address_records.length.nonzero?
    end

    def lookup_addresses(name)
      # 優先度の高いレコードを検索
      records = @address_records.select {|i| i['priority'] == MASTER }

      # レコードが見つからなかった場合は優先度の低いレコードを選択
      records = @address_records if records.empty?

      # IPアドレス、TTL、Weightを返す
      return records.map {|i| i.values_at('ip_address', 'ttl', 'weight') }
    ensure
      # エラー検出のため、一応クリア
      @address_records = nil
    end

    def name_exist?(address)
      address = x_ip_addr(address)

      # シングルスレッドェ…
      @name_records = @db.execute(<<-EOS, address, ACTIVE)
        SELECT name, ttl, priority FROM records
        WHERE ip_address = ? AND activity = ?
      EOS

      @name_records.length.nonzero?
    end

    def lookup_name(address)
      # 優先度の高いレコードを検索
      record = @name_records.find {|i| i['priority'] == MASTER }

      # レコードが見つからなかった場合は優先度の低いレコード選択
      record = @name_records.first unless record

      # ホスト名、TTLを返す
      return record.values_at('name', 'ttl')
    ensure
      # エラー検出のため、一応クリア
      @name_records = nil
    end

    private

    # リソースレコードのデータベース作成
    # もう少し並列処理に強いストレージに変えたいが…
    def create_database
      @db = SQLite3::Database.new(':memory:')
      @db.type_translation = true
      @db.results_as_hash = true

      # リソースレコード用のテーブル
      # （Typeは必要？）
      @db.execute(<<-EOS)
        CREATE TABLE records (
          ip_address TEXT PRIMARY KEY NOT NULL
          , name     TEXT NOT NULL
          , ttl      INTEGER NOT NULL
          , weight   INTEGER NOT NULL
          , priority INTEGER NOT NULL /* MASTER:1, BACKUP:0 */
          , activity INTEGER NOT NULL /* Active:1, Inactive:0 */
        )
      EOS

      # インデックスを作成（必要？）
      @db.execute(<<-EOS)
        CREATE INDEX idx_name_act
        ON records (name, activity)
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
