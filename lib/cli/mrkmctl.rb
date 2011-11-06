require 'cli/mrkmctl_options'

# オプションをパース
options = parse_args
p options

there = DRbObject.new_with_uri("drbunix:#{@@options[:sock]}")

there.database.execute('SELECT * FROM records').each do |r|
  p r
end
