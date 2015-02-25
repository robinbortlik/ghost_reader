require 'spec_helper'

describe GhostReader::Backend do

  let(:dev_null) { File.new('/dev/null', 'w') }

  let(:client) do
    double("Client").tap do |client|
      response = {'en' => {'this' => {'is' => {'a' => {'test' => 'This is a test.'}}}}}
      allow(client).to receive(:initial_request).and_return(:data => response)
      allow(client).to receive(:incremental_request).and_return(:data => response)
      allow(client).to receive(:reporting_request)
    end
  end

  context 'on class level' do
    it 'should nicely initialize' do
      expect(GhostReader::Backend.new( :logfile => dev_null )).to be_instance_of(GhostReader::Backend)
    end
  end

  context 'Backend set up with fallback' do

    let(:translation) { 'This is a test.' }

    let(:fallback) do
      double("FallbackBackend").tap do |fallback|
        allow(fallback).to receive(:lookup).and_return(translation)
      end
    end

    let(:backend) do
      GhostReader::Backend.new( :logfile => dev_null,
                                :log_level => Logger::DEBUG,
                                :fallback => fallback )
    end

    it 'should use the given fallback' do
      expect(backend.config.fallback).to be(fallback)
      expect(fallback).to receive(:lookup)
      expect(backend.translate(:en, 'this.is.a.test')).to eq(translation)
    end

    it 'should track missings' do
      backend.missings = {} # fake init
      backend.translate(:en, 'this.is.a.test')
      expect(backend.missings.keys).to eq(['this.is.a.test'])
    end

    it 'should use memoization' do
      expect(fallback).to receive(:lookup).exactly(1)
      2.times { expect(backend.translate(:en, 'this.is.a.test')).to eq(translation) }
    end

    it 'should symbolize keys' do
      test_data = { "one" => "1", "two" => "2"}
      result = backend.send(:symbolize_keys, test_data)
      expect(result.has_key?(:one)).to be_truthy
    end

    it 'should nicely respond to available_locales' do
      expect(backend).to respond_to(:available_locales)

      expected = [:en, :de]
      allow(fallback).to receive(:available_locales).and_return(expected)
      expect(backend.available_locales).to eq(expected)

      # FIXME
      # backend.send(:memoize_merge!, :it => {'dummay' => 'Dummy'})
      # backend.translate(:it, 'this.is.a.test')
      # backend.available_locales.should eq([:it, :en, :de])
    end

    context 'nicely merge data into memoized_hash' do

      it 'should work with valid data' do
        data = {'en' => {'this' => {'is' => {'a' => {'test' => 'This is a test.'}}}}}
        backend.send(:memoize_merge!, data)
        expect(backend.send(:memoized_lookup)).to have_key(:en)
        # flattend and symbolized
        expect(backend.send(:memoized_lookup)[:en]).to have_key(:'this.is.a.test')
      end

      it 'should handle weird data gracefully' do
        expect do
          data = {'en' => {'value_is_an_hash' => {'1st' => 'bla', '2nd' => 'blub'}}}
          backend.send(:memoize_merge!, data)
          data = {'en' => {'empty_value' => ''}}
          backend.send(:memoize_merge!, data)
          data = {'en' => {'' => 'Empty key.'}}
          backend.send(:memoize_merge!, data) # 'interning empty string'
          data = {'en' => {'value_is_an_array' => %w(what the fuck)}}
          backend.send(:memoize_merge!, data)
        end.to_not raise_error
      end

      # key should not be empty but if it is...
      # I18n::Backend::Flatten#flatten_translations is no longer raising error for empty key
      xit 'should not raise error when key is empty' do
        data = {'en' => {'' => 'Empty key.'}}
        backend.send(:memoize_merge!, data) # 'interning empty string'
        expect(backend.send(:memoized_lookup)).to be_empty
      end

    end

  end

  context 'GhostReader set up without fallback' do
    let(:backend) { GhostReader::Backend.new(:logfile => dev_null) }

    it 'should raise an error' do
      expect { backend.translate(:de, :asdf) }.to raise_error('no fallback given')
    end
  end

  context 'GhostReader set up with raising fallback' do
    let(:fallback) do
      double("FallbackBackend").tap do |fallback|
        allow(fallback).to receive(:lookup) do
          raise 'missing translation'
        end
      end
    end

    let(:backend) do
      GhostReader::Backend.new( :logfile => dev_null,
                                :log_level => Logger::DEBUG,
                                :fallback => fallback,
                                :client => client )
    end

    it 'should behave nicely' do
      expect { backend.translate(:de, :asdf) }.to raise_error('missing translation')
    end

    it 'should track lookups which raise exceptions' do
      # backend.retriever.should be_alive
      backend.missings = {} # fake initialize
      expect(backend.missings).to be_empty
      expect { backend.translate(:de, :asdf) }.to raise_error('missing translation')
      expect(backend.missings).not_to be_empty
    end
  end

end
