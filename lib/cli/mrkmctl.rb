require 'drb/drb'

require 'cli/mrkmctl_options'

# オプションをパース
options = parse_args
p options

there = DRbObject.new_with_uri("drbunix:#{options[:socket]}")

p there.records
#  p i
#end
