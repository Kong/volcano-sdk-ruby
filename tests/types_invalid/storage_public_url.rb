# frozen_string_literal: true

bucket = Volcano::StorageBucket.new(Object.new, Object.new, 'assets', api_url: 'https://api.example.test')
bucket.get_public_url(42)
