# frozen_string_literal: true

Volcano::FunctionResponse.new(data: nil, status: 200, headers: {}, version: nil, extra: true)
Volcano::FunctionResponse.new(data: nil, status: '200', headers: {}, version: nil)
Volcano::FunctionResponse[{}, 200, {}, 7]
Volcano::FunctionResponse.new(data: nil, status: 200, headers: {}, version: nil).with(headers: { 'x' => 7 })
Volcano::FunctionResponse.new(data: nil, status: 200, headers: {}, version: nil).deconstruct_keys
