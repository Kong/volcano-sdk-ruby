# frozen_string_literal: true

channel = Volcano::Client.new(anon_key: 'anon-key').realtime.channel('room')
channel.on('mesage') { nil }
