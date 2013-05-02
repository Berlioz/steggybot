require 'cinch'
require 'nokogiri'
require 'pry'
require 'open-uri'

class Pazudora
  include Cinch::Plugin
  
  PUZZLEMON_BASE_URL = "http://www.puzzledragonx.com/en/"
  GACHA_URL = "http://www.puzzledragonx.com/egg.asp"
  RANK_TABLE_URL = "http://www.puzzledragonx.com/en/levelchart.asp"
  
  match /pazudora ([\w-]+) *(.+)*/i, method: :pazudora
  match /stupidpuzzledragonbullshit ([\w-]+) *(.+)*/i, method: :pazudora
  match /stupiddragonpuzzlebullshit ([\w-]+) *(.+)*/i, method: :pazudora
  match /p&d ([\w-]+) *(.+)*/i, method: :pazudora
  match /pad ([\w-]+) *(.+)*/i, method: :pazudora
  match /puzzlemon ([\w-]+) *(.+)*/i, method: :pazudora
  match /puzzledex (.+)*/i, method: :pazudora_lookup
  
  @help_string = <<-eos
  Puzzle and Dragons (on iOS and Android) utility functions. Mostly collects friend codes and tracks the daily dungeon.
  Its commands are aliased to pazudora, p&d, pad, and puzzlemon.
  eos
  @help_hash = {
    :add => "Usage: !puzzlemon add NAME CODE
Example: !puzzlemon add steggybot 123,456,789
Adds user's code to the list of friend codes",
    :group => "Usage: !puzzlemon group NAME
Example !puzzlemon group steggybot
Returns the daily dungeon group that the user belongs to.",
    :dailies => "Usage: !puzzlemon dailies
Example !puzzlemon dailies
Returns the times (and type) of today's daily dungeons, split by group. If called by
a registered player, also reminds them of their group id. Buggy.",
    :lookup => "Usage: !(puzzlemon lookup|puzzledex) (NAME|ID)
Example !puzzlemon lookup horus, !puzzledex 603
Returns a description of the puzzlemon. Aliases: dex",
    :list => "Usage: !puzzlemon list
Example !puzzlemon list
Returns a list of everyone's friends codes.",
    :chain => "Usage: !puzzlemon chain (NAME|ID)
Example !puzzlemon chain siren
Returns a sumary of the given puzzlemon's evolutionary family.",
    :evolution => "Usage: !puzzlemon evolution
Example !puzzlemon evolution siren
Returns the set of evo materials necessary to advance to the next tier. Aliases: materials, mats, evolve",
    :experience => "Usage: !puzzlemon experience [FROM]
Example !puzzlemon siren 24
Calculates the amount of experience required to max out this puzzlemon. From defaults to 1.
Aliases: exp, level. YES I KNOW THERE ARE NO LIGHT/DARK PENGDRAS A BLOOO BOO HOO",
   :rank => "Usage: !puzzlemon rank (RANK|TO FROM)
Example !puzzlemon rank 60, !puzzlemon rank 100 120
Returns information about a given player rank, or calculates the deltas between them.
Reverse lookup also possible: !puzzlemon rank stamina 100 computes when you will get 100 stamina.",
   :gacha => "Usage: !puzzlemon gacha
Simulates a pull from the rare egg machine. No, this doesn't take events or weighting into account and is in fact almost certainly horrifyingly wrong in every particular.
User !puzzlemon gacha MONSTER to learn how many rolls you'll need to get that monster, e.g !pad gacha Horus
Are you feeling lucky? This command can change that. Aliases: pull, roll",
   :stamina => "Usage: !puzzlemon stamina START END TIMEZONE
Computes how long it will take to go from START (default 0) to END stamina, and when it will happen in your timezone.
Input your timezone as an integer UTC offset, e.g +7 or -11. Defaults to -7 (pacific standard)."
  }

  HELP = @help_hash

  ALIAS = {
    "delete" => "remove",
    "dex" => "lookup",
    "evolve" => "evolution",
    "materials" => "evolution",
    "mats" => "evolution",
    "xp" => "experience",
    "exp" => "experience",
    "level" => "experience",
    "pull" => "gacha",
    "roll" => "gacha",
    "stam" => "stamina"
  }
  
  def initialize(*args)
    super
    @pddata = config[:pddata]
  end
  
  #Any public method named pazudora_[something] is external and
  #can be accessed by the user using the construction "!puzzlemon something [args]".
  def pazudora (m, cmd, args)
    subr = cmd.downcase.chomp
    subr = ALIAS[subr] || subr
    begin
      if args
        self.send("pazudora_#{subr}", m, args)
      else
        self.send("pazudora_#{subr}", m, "")
      end
    rescue NoMethodError
      puts "Pazudora called with invalid command #{subr}."
      raise
    end
  end

  def pazudora_help(m, args)
    if args == ""
      r = "Usage: !pad help COMMAND.\n"
      r += "Registered commands are: #{HELP.keys.join(', ')}"
      m.reply r
    else
      helpstr = HELP[args.to_sym]
      m.reply "Unknown subcommand #{args}" and return unless helpstr
      m.reply helpstr
    end
  end
  
  def pazudora_add (m, args)
    pargs = args.split
    username = pargs[0]
    friend_code = pargs[1]
    
    # add it to the list
    friend_codes = load_data || {}
    if friend_code =~ /[0-9]{9}/
      friend_code = friend_code.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end 
    if friend_codes[username.downcase] && (friend_codes[username.downcase][:added_by] == username.downcase)
      if m.user.nick.downcase == username.downcase
        friend_codes[username.downcase] = {:friend_code => friend_code, :added_by => m.user.nick.downcase, :updated_at => DateTime.now}
      else
        m.reply "#{m.user.nick}: Can't override a user's self-definition."
        return
      end
    else
      friend_codes[username.downcase] = {:friend_code => friend_code, :added_by => m.user.nick.downcase, :updated_at => DateTime.now}
    end
    # write it to the file
    output = File.new(@pddata, 'w')
    output.puts YAML.dump(friend_codes)
    output.close
      
    m.reply "#{m.user.nick}: #{mangle(username)} successfully added as '#{friend_code}'."
  end
  
  def pazudora_remove(m, args)
    pargs = args.split
    username = pargs[0]
    friend_codes = load_data || {}
    
    if !friend_codes[username]
      m.reply "#{m.user.nick}: #{mangle(username)} not in friend code list."
      return
    end
    
    if (m.user.nick.downcase == username.downcase) || (m.user.nick.downcase == friend_codes[username][:added_by])
      friend_codes.delete(username)
      # write it to the file
      output = File.new(@pddata, 'w')
      output.puts YAML.dump(friend_codes)
      output.close
      
      m.reply "#{m.user.nick}: #{mangle(username)} removed from friend code list."
    else
      m.reply "#{m.user.nick}: Only the identity creator or subject can remove a friend code from the list."
    end
  end
  
  def pazudora_who(m,args)
    pargs = args.split
    username = pargs[0]
    if load_data[username.downcase]
      m.reply "#{m.user.nick}: #{mangle(username)}'s friend code is #{load_data[username.downcase][:friend_code]}"
    end
  end
  
  def pazudora_list(m,args)
    friend_codes = load_data || {}
    friend_codes.keys.each_slice(3).with_index { |users, i| 
      r = i == 0 ? "#{m.user.nick}: " : ""
      users.each{ |user| r=r+"#{mangle(user)}:#{friend_codes[user][:friend_code]} " }
      m.reply r
    }
  end
  
  def pazudora_group(m,args)
    pargs = args.split
    username = pargs[0]
    if load_data[username.downcase]
      friend_code = load_data[username.downcase][:friend_code]
      group = (Integer(friend_code.split(",")[0][2]) % 5 + 65).chr
      m.reply "#{m.user.nick}: #{mangle(username)}'s group is #{group}"
    else
      m.reply "#{m.user.nick}: #{mangle(username)}'s friend code is not listed. Please use the add command to add it."
    end
  end
  
  def pazudora_dailies(m, args)
    daily_url = PUZZLEMON_BASE_URL + "option.asp?utc=-8"
    
    username = args.split[0] || m.user.nick
    friend_code = load_data[username.downcase][:friend_code] rescue nil
    group_num = friend_code ? group_number_from_friend_code(friend_code) : nil
    
    unless @daily_timestamp == Time.now.strftime("%m-%d-%y")
      @daily_page = nil
      @daily_timestamp = Time.now.strftime("%m-%d-%y")
    end
    
    @daily_page ||= Nokogiri::HTML(open(daily_url))
    event_data = @daily_page.css(".event3")
    event_rewards = @daily_page.css(".limiteddragon")
    
    rewards = parse_daily_dungeon_rewards(event_rewards)
    m.reply "Dungeons today are: #{rewards.join(', ')}"
    
    (0..4).each do |i|
      m.reply "Group #{(i + 65).chr}: #{event_data[i].text}, #{event_data[i + 5].text}, #{event_data[i + 10].text}"
    end
    
    if group_num
      m.reply "User #{username} is in group #{(group_num + 65).chr}"
    end
  end
  
  def pazudora_lookup(m, args)
    identifier = args
    pdx = PazudoraData.instance.get_puzzlemon(identifier)
    m.reply "Could not find puzzlemon #{identifier}" and return if pdx.nil?
    m.reply pdx.lookup_output
  end

  def pazudora_chain(m, args)
    identifier = args
    pdx = PazudoraData.instance.get_puzzlemon(identifier)
    m.reply "Could not find puzzlemon #{identifier}" and return if pdx.nil?
    m.reply pdx.chain_output
  end

  def pazudora_evolution(m, args)
    identifier = args
    pdx = PazudoraData.instance.get_puzzlemon(identifier)
    m.reply "Could not find puzzlemon #{identifier}" and return if pdx.nil?
    m.reply pdx.mats_output
  end

  def pazudora_experience(m, args)
    argv = args.split(" ")
		if is_numeric?(argv.last)
	    from = argv.pop.to_i
    else
      from = 1
	  end
    identifier = args
    pdx = PazudoraData.instance.get_puzzlemon(identifier)
    m.reply "Could not find puzzlemon #{identifier}" and return if pdx.nil?
    m.reply pdx.experience_output(from)
  end

  def pazudora_stamina(m, args)
    argv = args.split(" ")
    if argv.last.match(/(\+|\-)\d+/)
      timezone = argv.pop
      offset = timezone.to_i
      offset = offset * -1 if offset < 0
      if offset > 0 && offset < 10
        offset = "0#{offset}"
      elsif offset >= 24
        m.reply "Invalid UTC offset #{offset}" and return
      else
        offset = offset.to_s
      end
      utc = "#{timezone[0,1]}#{offset}:00"
    else
      utc = "-07:00"
    end

    argv = argv.map(&:to_i)
    if argv.length == 2
      from = argv.first
      to = argv.last
    elsif argv.length == 1
      from = 0
      to = argv.last
    else
      m.reply "USAGE: !pad stamina TO? FROM TIMEZONE?"
    end

    stamina_delta = to - from
    time_delta = stamina_delta * 60 * 10
    target_time = Time.now + time_delta
    target_time = target_time.getlocal(utc)
    r = "You will gain #{stamina_delta} stamina (#{from}-#{to}) in ~#{stamina_delta * 10} minutes," +
        target_time.strftime(" or around %I:%M%p UTC") + utc
    m.reply r
  end

  def pazudora_gacha(m, args)
    argv = args.split(" ")
    if !argv.last.nil? && argv.last.match(/\+\S+/)
      godfest_flags = argv.last.split(//)[1..-1].map(&:upcase)
      args = args.split("+").first.strip
    else
      godfest_flags = []
    end

    if args == "tags" || args == "list_tags"
      r = "Use +[tags] to denote godfest; for example !pad pull +JGO for a japanese/greek/odins fest.\n"
      r += "Known tags: [R]oman, [J]apanese, [H]indu, [N]orse, [E]gyptian, [G]reek, [O]dins"
      m.reply r
    elsif args == ""
      p godfest_flags
      pdx = PazudoraData.instance.gachapon(godfest_flags)
      stars = pdx.stars
      type = pdx.type
      name = pdx.name

      if name.include?("Golem") || name.include?("Guardian")
        golem = true
        name = e_a_r_t_h_g_o_l_e_m(name)
      end

      if stars >= 5 && type == "god" && !pdx.name.include?("Verche")
        msg =  (stars == 6 ? "Lucky bastard!" : "Lucky bastard.")
      elsif stars == 5
        msg = "Meh."
      elsif golem
        msg = "Y O U I D I O T."
      else
        msg = "I just saved you $5."
      end
      r = "You got #{name}, a #{stars}* #{type}. #{msg}"
      m.reply(r)
    else
      regex = false
      identifier = args.strip.downcase
      if identifier.match(/\A\/.*\/\z/)
        regex = true
        identifier = Regexp.new("#{identifier[1..-2]}")
      end
      attempts = 0
      pdx = nil
      loop do
        attempts = attempts + 1
        pdx = PazudoraData.instance.gachapon(godfest_flags)
        next unless pdx.valid?
        break if !regex && (pdx.name.downcase.include?(identifier) || pdx.id == identifier)
        break if regex && (pdx.name.downcase.match(identifier) || pdx.name.match(identifier))
        m.reply("Unable to roll #{identifier}") and return if attempts == 10000
      end
      m.reply("After #{attempts} attempts, you rolled a #{pdx.name}. (There goes $#{attempts * 5})")
    end
  end

  def pazudora_rank(m, args)
    argv = args.split(" ")
    if argv.length == 1
      data = rank_data[argv.first]
      m.reply("No data for rank #{argv.first}") and return unless data
      r = "Rank #{argv.first}: cost #{data[:cost]}, stamina #{data[:stamina]}, friends #{data[:friends]}, total experience #{data[:exp_total]}, next level #{data[:exp_next]}"
      r.gsub!("--", "??")
    elsif argv.length == 2 && ["cost", "stamina", "friends"].include?(argv.first)
      search_stat = argv.first.to_sym
      m.reply("Bad search value #{argv.last}") and return unless is_numeric?(argv.last)
      search_value = argv.last.to_i
      rank_data.each do |k, v|
        if v[search_stat].to_i >= search_value
          m.reply("You will get >= #{search_value} #{search_stat} at rank #{k}") and return
        end
      end
      m.reply("Unable to reverse lookup #{search_value} #{search_stat}") and return
    elsif argv.length == 2
      data = rank_data
      input = argv.map(&:to_i).sort
      alpha = data[input.first.to_s]
      omega = data[input.last.to_s]
      exp_data_missing = input.last >= 148

      delta_cost = omega[:cost].to_i - alpha[:cost].to_i
      delta_stamina = omega[:stamina].to_i - alpha[:stamina].to_i
      delta_friends = omega[:friends].to_i - alpha[:friends].to_i

      r = "Ranks #{input.first}-#{input.last}: cost +#{delta_cost}, stamina +#{delta_stamina}, friends +#{delta_friends}"

      if exp_data_missing
        r += ".\nWarning: PDX experience values missing for ranks >= 148"
      else
        delta_exp = omega[:exp_total].to_i - alpha[:exp_total].to_i
        r += ", experience +#{delta_exp}."
      end
    else
      r = "Usage: !pad rank n for data about rank n, !pad rank x y to compute deltas between x and y, !pad <field> n for reverse lookup"
    end
    m.reply(r)
  end
  
  protected
  def is_numeric?(str)
    begin
      !!Integer(str)
    rescue ArgumentError, TypeError
      false
    end
  end

  # convert a requirements td into a list of evolution materials
  def evo_material_list(td)
    material_elements = td.children.select{|element| element.name == "a"}
    material_elements.map do |element|
      element.children.first.attributes["title"].value
    end
  end

  def rank_data
    ranks = Nokogiri::HTML.parse(open(RANK_TABLE_URL).read)
    rows = ranks.xpath("//table[@id='tablechart']").first.children
    rv = {}
    rows[2..-1].each do |row|
      cells = row.children
      level = cells[0].children.to_s
      cost = cells[1].children.to_s
      stamina = cells[2].children.to_s
      friends = cells[3].children.to_s
      exp_total = cells[4].children.to_s
      exp_next = cells[5].children.to_s
      rv[level] = {cost:cost,
                   stamina:stamina, 
                   friends:friends,
                   exp_total:exp_total,
                   exp_next:exp_next}
    end
    rv
  end

  def mangle(s)
    s.chop + "." + s[-1]
  end

  def e_a_r_t_h_g_o_l_e_m(s)
    out = ""
    s.each_char do |chr|
      next if chr == " "
      out += chr.upcase
      out += " "
    end
    out.strip
  end
  
  def load_data
    datafile = File.new(@pddata, 'r')
    friend_codes = YAML.load(datafile.read)
    datafile.close
    return friend_codes
  end
  
  def group_number_from_friend_code(friend_code)
    return Integer(friend_code.split(",")[0][2]) % 5
  end
  
  def parse_daily_dungeon_rewards(rewards)
    puzzlemon_numbers = [
    rewards[0].children.first.attributes["src"].value.match(/thumbnail\/(\d+).png/)[1],
    rewards[5].children.first.attributes["src"].value.match(/thumbnail\/(\d+).png/)[1],
    rewards[10].children.first.attributes["src"].value.match(/thumbnail\/(\d+).png/)[1]]
    
    puzzlemon_numbers.map{|x| 
      get_puzzlemon_info(x).css(".name").children.first.text rescue "Unrecognized Name" }
  end
  
  def get_puzzlemon_info(name_or_number)
    search_url = PUZZLEMON_BASE_URL + "monster.asp?n=#{name_or_number}"
    puzzlemon_info = Nokogiri::HTML(open(search_url))
  end
end


