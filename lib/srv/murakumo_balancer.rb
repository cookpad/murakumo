module Murakumo

  class Balancer

    def initialize(hash, address, db, logger)
      @hash = hash
      @address = address
      @db = db
      @logger = logger
    end

    def sort(records, max_ip_num, name)
      # アルゴリズムに応じて振り分け
      self.send(@algo, records, max_ip_num, name)
    end

    private

    # 重み付きランダム（デフォルト）
    def random(records, max_ip_num, name)
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

    # ソースで宛先を固定
    def fix_by_src(records, max_ip_num, name)
    end
  end # Balancer

end # Murakumo
