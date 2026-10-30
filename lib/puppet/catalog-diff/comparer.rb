require 'puppet/util/diff'
require 'digest'
require File.expand_path(File.join(File.dirname(__FILE__), 'formater.rb'))

# Puppet::CatalogDiff
module Puppet::CatalogDiff
  # Comparer providers methods
  # to compare resources
  module Comparer
    # Creates an array of just the resource titles
    # it would be records like file["/foo"]
    def extract_titles(resources)
      titles = []

      resources.each do |resource|
        titles << resource[:resource_id]
      end

      titles
    end

    # Compares two sets of resources and prints the differences
    # if the two sets do not include the same resource counts
    # this will only print the resources available in both
    def compare_resources(old, new, options)
      resource_differences = {}
      differences_in_old = {}
      differences_in_new = {}
      string_differences = {}
      content_differences = {}
      parameters_in_old = {}
      parameters_in_new = {}
      old.each do |resource|
        new_resource = new.find { |res| res[:resource_id] == resource[:resource_id] }
        next if new_resource.nil?

        if options[:ignore_parameters]
          blacklist = options[:ignore_parameters].split(',')
          filter_parameters!(new_resource[:parameters], blacklist)
          filter_parameters!(resource[:parameters], blacklist)
        end

        sort_dependencies!(new_resource[:parameters])
        sort_dependencies!(resource[:parameters])

        next if new_resource[:parameters] == resource[:parameters]

        # Content can be huge, so only content_differences shows it as text
        cont_diff = str_diff(checksum_content!(resource[:parameters]), checksum_content!(new_resource[:parameters]))
        content_differences[resource[:resource_id]] = cont_diff if cont_diff

        parameters_in_old[resource[:resource_id]] =
          (resource[:parameters].to_a - new_resource[:parameters].to_a).to_h

        parameters_in_new[resource[:resource_id]] =
          (new_resource[:parameters].to_a - resource[:parameters].to_a).to_h

        if options[:show_resource_diff]
          Puppet.debug("Resource diff: #{resource[:resource_id]}")

          diff_array = str_diff(
            Puppet::CatalogDiff::Formater.new.resource_to_string(resource),
            Puppet::CatalogDiff::Formater.new.resource_to_string(new_resource),
          ).split("\n")
          if diff_array.size >= 3
            string_differences[resource[:resource_id]] = diff_array[3..-1]
          else
            Puppet.debug('Could not automatically detect diff')
            string_differences[resource[:resource_id]] = resource[:parameters].inspect + new_resource[:parameters].inspect
          end

        else
          differences_in_old[resource[:resource_id]] = resource

          differences_in_new[resource[:resource_id]] = new_resource
        end
      end
      resource_differences[:old] = differences_in_old
      resource_differences[:new] = differences_in_new
      resource_differences[:string_diffs] = string_differences
      resource_differences[:content_differences] = content_differences
      resource_differences[:old_params]  = parameters_in_old
      resource_differences[:new_params]  = parameters_in_new
      resource_differences
    end

    # Replaces content with its checksum and returns it as text,
    # or returns nil if it is not text
    def checksum_content!(params)
      text = params[:content]
      # Some types accept content as an array of lines
      text = text.map { |line| "#{line}\n" }.join if text.is_a?(Array) && text.all?(String)
      return nil unless text.is_a?(String)

      params[:content] = Digest::MD5.hexdigest(text)
      text
    end

    # filter parameters
    def filter_parameters!(params, blacklist)
      params.reject! { |p, _k| blacklist.include?(p.to_s) }
    end

    # sort require/before/notify/subscribe before comparison
    def sort_dependencies!(params)
      params.each do |x|
        next unless %i[require before notify subscribe].include?(x[0])

        x[1].sort! if x[1].instance_of?(Array)
      end
    end

    # Takes arrays of resource titles and shows the differences
    def return_resource_diffs(old, new)
      {
        titles_only_in_old: (old - new).map(&:to_s),
        titles_only_in_new: (new - old).map(&:to_s),
      }
    end

    def do_str_diff(str1, str2)
      paths = [str1, str2].map do |s|
        tempfile = Tempfile.new('puppet-diffing')
        tempfile.open
        tempfile.print s
        tempfile.close
        tempfile
      end
      diff = Puppet::Util::Diff.diff(paths[0].path, paths[1].path)
      paths.each(&:delete)
      diff
    end

    def validate_encoding(str)
      unless str.valid_encoding?
        Puppet.debug("Detected that string used in diff had invalid #{str.encoding} encoding. Replacing invalid characters in diff output.")
        str.encode!('UTF-8', 'UTF-8', invalid: :replace)
      end
      str
    end

    def str_diff(str1, str2)
      return nil unless str1 && str2

      sum1 = Digest::MD5.hexdigest(str1)
      sum2 = Digest::MD5.hexdigest(str2)
      return nil if sum1 == sum2

      str1 = validate_encoding(str1)
      str2 = validate_encoding(str2)

      @@cached_str_diffs ||= {}
      @@cached_str_diffs["#{sum1}/#{sum2}"] ||= do_str_diff(str1, str2)
    end
  end
end
