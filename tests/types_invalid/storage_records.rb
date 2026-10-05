# frozen_string_literal: true

Volcano::StorageObject.new(
  id: 'object', bucket_id: 'bucket', name: 'photo.png', size: '5',
  mime_type: 'image/png', is_public: false
)
Volcano::StorageObject.new(id: 'object', bucket_id: 'bucket')
Volcano::StorageObject['object', 'bucket', 'photo.png', 5, 'image/png', false]
  .with(metadata: ['not a map'])

Volcano::StoragePage.new(objects: ['not an object'])
Volcano::StoragePage[['not an object'], 'cursor']
