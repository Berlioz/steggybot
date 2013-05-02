require 'singleton'
require 'json'
require 'levenshtein'

class PazudoraData
  include Singleton

  attr_reader :monster_data
  attr_reader :exp_data
  attr_reader :rem_data

  def initialize
    @monster_data = JSON.parse(File.read("json/scraped_monsters.json"))
    @exp_data = JSON.parse(File.read("json/scraped_xp_curves.json"))
    @rem_data = JSON.parse(File.read("json/tags.json"))
    @name_map = {}
    @monster_data.each do |id, data|
      @name_map[data["name"].downcase] = id
    end
  end

  def get_puzzlemon(identifier)
    if identifier.to_i != 0
      id = identifier.to_i
      Puzzlemon.new(id, @monster_data[id.to_s])
    else
      match = substring_search(identifier)
      if match.nil?
        id = edit_distance_search(identifier)
        return nil if id.nil?
        Puzzlemon.new(id, @monster_data[id.to_s])
      else
        Puzzlemon.new(match, @monster_data[match.to_s])
      end
    end
  end

  def substring_search(identifier)
    names = @name_map.keys
    matches = names.select{|x| x.include?(identifier.downcase) }
    return nil if matches.empty?
    choice = matches[matches.map{|current| Levenshtein.distance(identifier.downcase, current)}.each_with_index.min.last]
    @name_map[choice]
  end

  def edit_distance_search(identifier)
    names = @name_map.keys
    choice = names[names.map{|current| Levenshtein.distance(identifier.downcase, current)}.each_with_index.min.last]
    return nil if Levenshtein.distance(identifier.downcase, choice) > 3
    @name_map[choice]
  end

  def gachapon(tags=[])
    godfest = []
    tags.each do |tag|
      next if @rem_data[tag].nil?
      godfest = godfest + @rem_data[tag] + @rem_data[tag + "6"]
    end

    id = (@rem_data["REM"] + godfest).sample.to_s
    Puzzlemon.new(id, @monster_data[id])
  end
end

class Puzzlemon
  def initialize(id, json)
    @id = id
    @data = json
  end

  def valid?
    !@data.nil? && !@id.nil?
  end

  def id
    @id
  end

  def name
    @data["name"]
  end

  def max_level
    @data["max_level"]
  end

  def max_xp
    curve = @data["curve"]
    return 0 if curve.nil?
    exp_values = PazudoraData.instance.exp_data[curve]
    exp_values[max_level.to_s]
  end

  def stat_line(statname)
    min = @data["#{statname}_min"]
    max = @data["#{statname}_max"]
    "#{min}-#{max}"
  end

  def skill
    @data["skill_text"]
  end

  def leaderskill
    @data["leader_text"]
  end

  def stars
    @data["stars"]
  end

  def element
    @data["element"]
  end

  def cost
    @data["cost"]
  end

  def type
    @data["type"]
  end

  def lookup_output
    r = "No. #{id} #{name}, a #{stars}* #{element} #{type} monster.\n"
    r += "Deploy Cost: #{cost}. Max level: #{max_level}, #{max_xp} XP to max.\n"
    r += "HP #{stat_line("hp")}, ATK #{stat_line("atk")}, RCV #{stat_line("rcv")}, BST #{stat_line("bst")}\n"
    r += "#{skill}"
    r += "#{leaderskill}"
    r
  end

  def chain_output
    @data["evo_chain"].length > 0 ?
        "#{name}'s evolution chain: " + @data["evo_chain"].join(", ") :
        "Puzzlemon #{name} is not part of an evolution chain."
  end

  def mats_output
    mats = @data["evo_mats"]
    return "Puzzlemon #{name} does not evolve." if mats.flatten.empty?
    r = "#{name} evolution materials:\n"
    if mats.first.class == Array
      r += mats.map do |branch|
        branch.join(", ")
      end.join("\n\t-or-\t\n")
    else
      r += mats.join("\n")
    end
    r
  end

  def experience_output(from)
    curve = @data["curve"]
    return "Puzzlemon #{name} does not level" if curve.nil?
    exp_values = PazudoraData.instance.exp_data[curve]
    delta = exp_values[max_level.to_s] - exp_values[from.to_s]
    pengies = (delta / 45000.0).round(2)
    offcolor_pengies = (delta / 30000.0).round(2)
    return "To get #{name} from #{from} to #{max_level} takes #{delta}xp, or #{pengies} (#{offcolor_pengies} offcolor) pengdras. Get farming!"
  end
end