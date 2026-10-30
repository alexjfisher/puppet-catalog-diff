require 'spec_helper'
require 'puppet/catalog-diff/comparer'

describe Puppet::CatalogDiff::Comparer do
  include described_class

  let(:res1) do
    [
      {
        resource_id: 'file.foo',
        type: 'file',
        parameters: {
          name: 'foo',
          alias: 'baz',
          path: '/foo',
          content: 'foo content',
        },
      },
    ]
  end

  let(:res2) do
    [
      {
        resource_id: 'file.foo',
        type: 'file',
        parameters: {
          name: 'foo',
          alias: 'baz',
          path: '/food',
          content: 'foo content 2',
        },
      },
    ]
  end

  let(:resources1) do
    [
      {
        resource_id: 'foo',
      },
      {
        resource_id: 'bar',
      },
    ]
  end

  let(:resources2) do
    [
      {
        resource_id: 'foo',
      },
      {
        resource_id: 'baz',
      },
    ]
  end

  describe 'extract_titles' do
    it 'returns resource ids' do
      extract_titles(resources1).should eq(%w[foo bar])
    end
  end

  describe 'compare_resources' do
    it 'returns a diff without options' do
      diffs = compare_resources(res1, res2, {})
      expect(diffs[:old]).to eq(res1[0][:resource_id] => res1[0])
      expect(diffs[:new]).to eq(res2[0][:resource_id] => res2[0])
      expect(diffs[:old_params]).to eq('file.foo' => { content: '6dbda444875c24ec1bbdb433456be11f', path: '/foo' })
      expect(diffs[:new_params]).to eq('file.foo' => { content: '4eb91aa4f5795ef3658d1e0a2798c816', path: '/food' })
      expect(diffs[:content_differences]['file.foo']).to match(%r{^\+foo content 2$})
      expect(diffs[:string_diffs]).to be_empty
    end

    it 'returns string_diffs with show_resource_diff' do
      diffs = compare_resources(res1, res2, show_resource_diff: true)
      expect(diffs[:string_diffs]['file.foo']).to include(
        "-\t     content => \"6dbda444875c24ec1bbdb433456be11f\"",
        "+\t     content => \"4eb91aa4f5795ef3658d1e0a2798c816\"",
      )
      expect(diffs[:content_differences]['file.foo']).to match(%r{^\+foo content 2$})
    end

    it 'returns content_differences with content encoded in ISO8859-1 (latin1)' do
      # Without this the unit test fails when running on LC_ALL=C but works with LC_ALL=en_US.UTF-8
      # With this it works on both.
      Encoding.default_internal = 'UTF-8'
      Encoding.default_external = 'UTF-8' # Needed because diff uses tempfile.

      latin1_string = [246].pack('C*').force_encoding('UTF-8')
      res1[0][:parameters][:content] = latin1_string
      diffs = compare_resources(res1, res2, {})

      ruby_default_replacement_string_for_invalid_characters = '�'
      expect(diffs[:content_differences]['file.foo']).to \
        match(%r{^-#{ruby_default_replacement_string_for_invalid_characters}$})
    end

    it 'returns a diff without path parameter' do
      diffs = compare_resources(res1, res2, ignore_parameters: 'path')
      expect(diffs[:old_params]).to eq('file.foo' => { content: '6dbda444875c24ec1bbdb433456be11f' })
      expect(diffs[:new_params]).to eq('file.foo' => { content: '4eb91aa4f5795ef3658d1e0a2798c816' })
    end

    it 'diffs content given as an array of strings' do
      res1[0][:parameters][:content] = %w[foo bar]
      res2[0][:parameters][:content] = %w[foo bar baz]
      diffs = compare_resources(res1, res2, {})
      expect(diffs[:new_params]['file.foo'][:content]).to eq(Digest::MD5.hexdigest("foo\nbar\nbaz\n"))
      expect(diffs[:content_differences]['file.foo']).to match(%r{^ bar\n\+baz\n\z})
    end

    it 'leaves content that is not text unchanged' do
      res1[0][:parameters][:content] = ['foo', 1]
      res2[0][:parameters][:content] = ['foo', 2]
      diffs = compare_resources(res1, res2, {})
      expect(diffs[:new_params]['file.foo'][:content]).to eq(['foo', 2])
      expect(diffs[:content_differences]).to be_empty
    end
  end

  describe 'return_resource_diffs' do
    it 'returns differences' do
      diffs = return_resource_diffs(extract_titles(resources1), extract_titles(resources2))
      expect(diffs[:titles_only_in_old]).to eq(['bar'])
      expect(diffs[:titles_only_in_new]).to eq(['baz'])
    end
  end

  describe 'do_str_diff' do
    it 'diffs two strings' do
      diff = do_str_diff('abc', 'abd')
      expect(diff).to match(%r{^-abc$})
      expect(diff).to match(%r{^\+abd$})
    end
  end

  describe 'str_diff' do
    context 'when passing strings' do
      it 'diffs two strings' do
        diff = str_diff('abc', 'abd')
        expect(diff).to match(%r{^-abc$})
        expect(diff).to match(%r{^\+abd$})
      end
    end

    context 'when passing equal strings' do
      it 'returns nil' do
        expect(str_diff('abc', 'abc')).to be_nil
      end
    end
  end
end
