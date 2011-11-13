require 'forwardable'
require 'rgossip2'
require 'sqlite3'

require 'misc/murakumo_const'

module Murakumo

  class Cloud
    extend Forwardable

    def initialize(options)
      # オプションはインスタンス変数に保存
      @options = options

      # リソースレコードからホストのアドレスとデータを取り出す
      host_data = options[:host]
      @address = host_data.shift
      host_data.concat [ORIGIN, ACTIVE]
      alias_datas = options[:aliases].map {|r| r + [ACTIVE] }

      # データベースを作成してレコードを更新
      create_database
      update(@address, [host_data] + alias_datas)

      # ゴシップオブジェクトを生成
      @gossip = RGossip2.client({
        :initial_nodes   => options[:initial_nodes],
        :address         => @address,
        :data            => [host_data] + alias_datas,
        :auth_key        => options[:auth_key],
        :port            => options[:gossip_port],
        :node_lifetime   => options[:gossip_node_lifetime],
        :gossip_interval => options[:gossip_send_interval],
        :receive_timeout => options[:gossip_receive_timeout],
        :logger          => options[:logger],
      })

      # ノードの更新をフック
      @gossip.context.callback_handler = lambda do |act, addr, ts, dt|
        case act
        when :add, :comeback, :update
          update(addr, dt)
        when :delete
          delete(addr)
        end
      end

      # XXX: ヘルスチェックの実装
    end

    # Control of service
    def_delegators :@gossip, :start, :stop

    def to_hash
      keys = {
        :auth_key      => 'auth-key',
        :dns_address   => 'address',
        :dns_port      => 'port',
        :initial_nodes => lambda {|v| ['initial-nodes', v.join(',')] },
        :resolver      => lambda {|v| [
          'resolver',
          v.instance_variable_get(:@config).instance_variable_get(:@config_info)[:nameserver]
        ]},
        :socket        => 'socket',
        :max_ip_num    => 'max-ip-number',
        :log_path      => 'log-path',
        :log_level     => 'log-level',
        :gossip_port   => 'gossip-port',
        :gossip_node_lifetime => lambda {|v| [
          'gossip-node-lifetime',
          @gossip.context.node_lifetime
        ]},
        :gossip_send_interval => lambda {|v| [
          'gossip-send-interval',
          @gossip.context.gossip_interval
        ]},
        :gossip_receive_timeout => lambda {|v| [
          'gossip-receive-timeout',
          @gossip.context.receive_timeout
        ]},
      }

      hash = {}

      keys.each do |k, name|
        value = @options[k]

        if name.respond_to?(:call)
          name, value = name.call(value)
        end

        hash[name] = value if value
      end

      records = list_records

      hash['host'] = records.find {|r| r[3] == ORIGIN }[0..2].join(',')

      aliases = records.select {|r| r[3] != ORIGIN }.map do |r|
        [r[1], r[2], (r[3] == MASTER ? 'master' : 'backup')].join(',')
      end

      hash['alias'] = aliases unless aliases.empty?

      return hash
    end

    def list_records
      columns = %w(ip_address name ttl priority activity)

      @db.execute(<<-EOS).map {|i| i.values_at(*columns) }
        SELECT #{columns.join(', ')} FROM records ORDER BY ip_address, name
      EOS
    end

    def add_or_rplace_records(records)
      errmsg = nil

      @gossip.transaction do

        # 既存のホスト名は削除
        @gossip.data.reject! do |d|
          if records.any? {|r| r[0] == d[0] }
            # オリジンのPriorityは変更不可
            if d[2] == ORIGIN
              records.each {|r| r[2] = ORIGIN if r[0] == d[0] }
            end

            true
          end
        end

        # データを更新
        records = records.map {|r| r + [ACTIVE] }
        @gossip.data.concat(records)
      end # transaction

      # データベースを更新
      update(@address, records, true)

      return [!errmsg, errmsg]
    end

    def delete_records(names)
      errmsg = nil

      @gossip.transaction do
        # データを削除
        @gossip.data.reject! do |d|
          if names.any? {|n| n == d[0] }
            if d[2] == ORIGIN
              # オリジンは削除不可
              errmsg = 'original host name cannot be deleted'
              names.reject! {|n| n == d[0] }
              false
            else
              true
            end
          end
        end
      end # transaction

      # データベースを更新
      delete_by_names(@address, names)

      return [!errmsg, errmsg]
    end

    def add_nodes(nodes)
      errmsg = nil

      nodes.each do |i|
        @gossip.add_node(i)
      end

      return [!errmsg, errmsg]
    end

    def delete_nodes(nodes)
      errmsg = nil

      nodes.each do |i|
        @gossip.delete_node(i)
      end

      return [!errmsg, errmsg]
    end

    def get_attr(name)
      return unless ATTRIBUTES.has_key?(name)

      if name == :log_level
        if @gossip.logger
          %w(debug info warn error fatal)[@gossip.logger.level]
        else
          nil
        end
      else
        attr, conv = ATTRIBUTES[name]
        @gossip.context.send(attr).to_s
      end
    end

    def set_attr(name, value)
      return unless ATTRIBUTES.has_key?(name)

      errmsg = nil

      if name == :log_level
        if @gossip.logger
          @gossip.logger.level = %w(debug info warn error fatal).index(value.to_s)
        end
      else
        attr, conv = ATTRIBUTES[name]
        @gossip.context.send("#{attr}=", value.send(conv)).to_s
      end

      return [!errmsg, errmsg]
    end

    def close
      # データベースをクローズ
      @db.close
    end

    # Operation of storage 

    def update(address, datas, update_only = false)
      return unless datas

      datas.each do |i|
        @db.execute(<<-EOS, address, *i)
          REPLACE INTO records (ip_address, name, ttl, priority, activity)
          VALUES (?, ?, ?, ?, ?)
        EOS
      end

      # データにないレコードは消す
      unless update_only
        names = datas.map {|i| "'#{i.first}'" }.join(',')

        @db.execute(<<-EOS, address)
          DELETE FROM records
          WHERE ip_address = ? AND name NOT IN (#{names})
        EOS
      end
    end

    def delete(address)
      @db.execute('DELETE FROM records WHERE ip_address = ?', address)
    end

    def delete_by_names(address, names)
      names = names.map {|i| "'#{i}'" }.join(',')

      @db.execute(<<-EOS, address)
        DELETE FROM records
        WHERE ip_address = ? AND name IN (#{names})
      EOS
    end

    # Search of records

    def address_exist?(name)
      # シングルスレッドェ…
      @address_records = @db.execute(<<-EOS, name, ACTIVE)
        SELECT ip_address, ttl, priority FROM records
        WHERE name = ? AND activity = ?
      EOS

      @address_records.length.nonzero?
    end

    def lookup_addresses(name)
      records = nil

      if @address_records.length == 1
        # レコードが一件ならそれを返す
        records = @address_records
      else
        # 優先度の高いレコードを検索
        records = @address_records.select {|i| i['priority'] == MASTER }

        # レコードが見つからなかった場合は優先度の低いレコードを選択
        if records.empty?
          records = @address_records.select {|i| i['priority'] == BACKUP }
        end

        # それでもレコードが見つからなかった場合はオリジンを選択
        # ※このパスは通らない
        records = @address_records if records.empty?
      end

      # IPアドレス、TTLを返す
      return records.map {|i| i.values_at('ip_address', 'ttl') }
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
      record = nil

      if @name_records.length == 1
        # レコードが一件ならそれを返す
        record = @name_records.first
      else
        # オリジンを検索
        record = @name_records.find {|i| i['priority'] == ORIGIN }

        # レコードが見つからなかった場合は優先度の高いレコード選択
        unless record
          record = @name_records.find {|i| i['priority'] == ACTIVE }
        end

        # それでもレコードが見つからなかった場合は優先度の低いレコードを選択
        record = @name_records.first unless record
      end

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
          ip_address TEXT NOT NULL,
          name       TEXT NOT NULL,
          ttl        INTEGER NOT NULL,
          priority   INTEGER NOT NULL, /* MASTER:1, BACKUP:0, ORIGIN:-1 */
          activity   INTEGER NOT NULL, /* Active:1, Inactive:0 */
          PRIMARY KEY (ip_address, name)
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
