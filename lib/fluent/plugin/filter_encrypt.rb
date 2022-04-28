require 'fluent/filter'
require 'openssl'
require 'base64'
require 'ffi'

module Fluent
  extend FFI::Library
  ffi_lib File.join(__dir__, 'go/encryptor.so')

  attach_function :encrypt, [:string, :string], :string
  attach_function :decrypt, [:string, :string], :string

  class EncryptFilter < Filter
    Fluent::Plugin.register_filter('encrypt', self)

    config_param :decrypt, :string, default: nil
    config_param :encrypt_key, :string
    config_param :keys, :array, default: []

    attr_reader :target_keys

    def configure(conf)
      super
      if @keys.empty?
        raise Fluent::ConfigError, "no keys specified to be encrypted"
      end

      
      @enc_generator = ->(){
        enc = OpenSSL::Cipher.new("AES-128-CBC")
        enc.encrypt
        enc.key = Base64.decode64(@encrypt_key)
        enc.iv  = Base64.decode64(@enc_iv) if @enc_iv
        enc
      }
      
      @dec_generator = ->(){
        dec = OpenSSL::Cipher.new("AES-128-CBC")
        dec.decrypt
        dec.key = Base64.decode64(@encrypt_key)
        dec.iv  = Base64.decode64(@enc_iv) if @enc_iv
        dec
      }
    end

    def encrypt(value)
      encrypted = ""
      enc = @enc_generator.call()
      encrypted << enc.update(value)
      encrypted << enc.final
      Base64.encode64(encrypted)
    end
    
    def decrypt(value)
      decrypted = ""
      enc = @dec_generator.call()
      decrypted << enc.update(Base64.decode64(value))
      decrypted << enc.final
      decrypted
    end

    def filter(tag, time, record)

    end

    def filter_stream(tag, es)
      new_es = MultiEventStream.new
      es.each do |time, record|
        r = record.dup
        record.each_pair do |key, value|
          if @keys.include?(key)
            if @decrypt
              r[key] = decrypt(value)
            else
              r[key] = encrypt(value)
            end
          end
        end
        new_es.add(time, r)
      end
      new_es
    end
  end
end
