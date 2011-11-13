require 'drb/drb'

require 'cli/mrkmctl_options'
require 'misc/murakumo_const'

# オプションをパース
options = parse_args
p options

there = DRbObject.new_with_uri("drbunix:#{options[:socket]}")

cmd, arg = options[:command]

case cmd

when :list
  records = if arg.kind_of?(String)
              # 引数がある場合はフィルタリング
              there.list_records.select {|r| r[0..1].any?{|i| i.start_with?(arg) } }
            else
              there.list_records
            end

  puts <<-EOF
IP address       TTL     Priority  Activity  Hostname
---------------  ------  --------  --------  ----------
  EOF
  records.each do |r|
    r[3] = (r[3] == Murakumo::MASTER ? 'Master' : 'Backup')
    r[4] = (r[4] == Murakumo::ORIGIN ? 'Origin' : r[4] == Murakumo::ACTIVE ? 'Active' : 'Inactive')
    puts '%-15s  %6d  %-8s  %-8s  %s' % r.values_at(0, 2, 3, 4, 1)
  end

when :add
  there.add_or_rplace_records(arg)
end
