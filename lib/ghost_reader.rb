%w( backend client ).each do |f|
  require File.expand_path(File.join(%w(.. ghost_reader), f), __FILE__)
end

if defined?(::Rails)
  %w( util engine ).each do |f|
    require File.expand_path(File.join(%w(.. ghost_reader), f), __FILE__)
  end
end
