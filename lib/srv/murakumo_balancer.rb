require 'misc/murakumo_const'

module Murakumo

  class Balancer

    def initialize(hash, address, db, logger)
      @hash = hash
      @address = address
      @db = db
      @logger = logger
    end

    def sort(records, max_ip_num, name)
      # ハッシュが空ならランダムで
      if @hash.nil? or @hash.empty?
        return random(records, max_ip_num)
      end

      # 宛先を検索
      dest, attrs = @hash.find {|k, v| k =~ name }

      if dest.nil? or attrs.nil?
        # 設定が見つからない場合はとりあえずランダムで
        return random(records, max_ip_num)
      end

      algo = attrs[:algorithm]
      max_ip_num = attrs[:max_ip_num] || max_ip_num
      sources = attrs[:sources]

      case algo
      when :random
        random(records, max_ip_num)
      when :fix_by_src
        fix_by_src(records, max_ip_num, sources)
      when :fix_by_src2
        fix_by_src2(records, max_ip_num, sources)
      else
        # 未対応のアルゴリズムの場合はとりあえずランダムで返す
        @logger.warn("distribution setup which is not right: #{[dest, algo].inspect}")
        random(records, max_ip_num)
      end
    end

    private

    # 重み付きランダム（デフォルト）
    def random(records, max_ip_num)
      indices = []
      buf = []

      # インデックスをWeight分追加
      records.each_with_index do |r, i|
        weight = r['weight']
        weight.times { buf << i }
      end

      # インデックスをシャッフル
      buf = buf.sort_by{ rand }

      # ランダムにインデックスを取り出す
      loop do
        indices << buf.shift
        indices.uniq!
        break if (indices.size >= max_ip_num or buf.empty?)
      end

      # インデックスのレコードを返す
      records.values_at(*indices)
    end

    def fix_by_src(records, max_ip_num, src_aliases)
      fix_by_src0(records, max_ip_num, src_aliases) do |new_records|
        # そのまま評価
        new_records.slice(0, max_ip_num)
      end
    end

    def fix_by_src2(records, max_ip_num, src_aliases)
      fix_by_src0(records, max_ip_num, src_aliases) do |new_records|
        # 先頭 + ランダムを返す
        first = new_records.shift
        [first] + new_records.slice(0, max_ip_num).sort_by { rand }
      end
    end

    # ソースで宛先を固定
    def fix_by_src0(records, max_ip_num, src_aliases)
      joined = src_aliases.map {|i| "'#{i.downcase}'" }.join(',')

      # ソースエイリアスでIPアドレスを探す
      sources = @db.execute(<<-EOS, ACTIVE).map {|i| i['ip_address'] }.sort
        SELECT ip_address FROM records
        WHERE name IN (#{joined}) AND activity = ?
      EOS

      # ソースが見つからない場合はとりあえずランダムで
      if sources.empty?
        @logger.warn("source is not found: #{src_aliases.join(',')}")
        return random(records, max_ip_num)
      end

      # ソースが自分を含んでいない場合はとりあえずランダムで
      unless sources.include?(@address)
        @logger.warn("sources does not contain self: #{@address}")
        return random(records, max_ip_num)
      end

      # 宛先をソート
      dests = (0...records.length).map {|i| [records[i]['ip_address'], i] }.sort_by {|a, b| a }

      # ソースが一つだけなら先頭のインデックスを返す
      if sources.length == 1
        return [records[dests.first[1]]]
      end

      # 数をそろえる
      if sources.length < dests.length
        dests.slice!(0, sources.length)
      elsif sources.length > dests.length
        dests = dests * (sources.length.to_f / dests.length).ceil
        dests.slice!(0, sources.length)
      end

      # 先頭を決めてローテート
      first_index = sources.zip(dests).index {|s, d| s == @address }

      unless first_index.zero?
        dests = (dests + dests).slice(first_index, dests.length)
      end

      # 先頭インデックスからレコードを並べ直す
      yield(records.values_at(*dests.map {|addr, i| i }))
    end # fix_by_src0

  end # Balancer

end # Murakumo
