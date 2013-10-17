class @AutoComplete

  @KEYS: [
    40, # DOWN
    38, # UP
    13, # ENTER
    27, # ESCAPE
    9   # TAB
  ]

  constructor: (settings) ->
    @limit = settings.limit || 5
    @position = settings.position || "bottom"

    @rules = settings.rules
    # Expressions compiled for range from last word break to current cursor position
    @expressions = (new RegExp('(^|>|\\s)' + rule.token + '([\\w.]*)$') for rule in @rules)

    @matched = -1
    @afterTokenPosition = 0

    # Reactive dependencies for current matching rule and filter
    @ruleDep = new Deps.Dependency
    @filterDep = new Deps.Dependency
    Session.set("-autocomplete-id", null); # Use this for Session.equals()

  onKeyUp: (e) ->
    if e.keyCode isnt 27
      startpos = @getCursorPosition() #@$element.getCursorPosition() # TODO: this doesn't seem to be correct on a focus
      val = @getText().substring(0, startpos)
      @tokenChanged = false

      ###
        Matching on multiple expressions.
        We always go from an matched state to an unmatched one
        before going to a different matched one.
      ###
      i = 0
      breakLoop = false
      while i < @expressions.length
        matches = val.match(@expressions[i])

        # matching -> not matching
        if not matches and @matched is i
          @matched = -1
          @ruleDep.changed()
          breakLoop = true

        # not matching -> matching
        if matches
          afterTokenPosition = val.lastIndexOf(@rules[i].token) + 1
          if @afterTokenPosition isnt afterTokenPosition
            @afterTokenPosition = afterTokenPosition
            @tokenChanged = true
            @ruleDep.changed()
            breakLoop = true

          if @matched is -1
            @matched = i
            @ruleDep.changed()
            breakLoop = true

          # Did filter change?
          if @filter isnt matches[2]
            @filter = matches[2]
            @filterDep.changed()
            breakLoop = true

        break if breakLoop
        i++

  onKeyDown: (e) =>
    return if @matched is -1 or (@constructor.KEYS.indexOf(e.keyCode) < 0)

    switch e.keyCode
      when 9, 13 # TAB, ENTER
        e.stopPropagation() if @select() # Don't jump fields or submit if select successful
      when 40
        @next()
      when 38
        @prev()
      when 27 # ESCAPE; not sure what function this should serve, cause it's vacuous in jquery-sew
        @hideList()

    e.preventDefault()

  onMouseup: (e) -> @onKeyUp(e)

  onBlur: ->
    # We need to delay this so click events work
    # TODO this is a bit of a hack; see if we can't be smarter
    Meteor.setTimeout =>
      @hideList()
    , 500

  onItemClick: (doc, e) =>
    @replace doc[@rules[@matched].field]
    @hideList()

  onItemHover: (doc, e) ->
    Session.set("-autocomplete-id", doc._id)

  # Replace text with currently selected item
  select: ->
    docId = Deps.nonreactive(-> Session.get("-autocomplete-id"))
    return false unless docId # Don't select if nothing matched

    rule = @rules[@matched]
    @replace rule.collection.findOne(docId)[rule.field]
    @hideList()
    return true

  # Select next item in list
  next: ->
    currentItem = @tmplInst.find(".-autocomplete-item.selected")
    return unless currentItem # Don't try to iterate an empty list

    next = $(currentItem).next()
    if next.length
      nextId = Spark.getDataContext(next[0])._id
    else # End of list or lost selection; Go back to first item
      nextId = Spark.getDataContext(@tmplInst.find(".-autocomplete-item:first-child"))._id
    Session.set("-autocomplete-id", nextId)

  # Select previous item in list
  prev: ->
    currentItem = @tmplInst.find(".-autocomplete-item.selected")
    return unless currentItem # Don't try to iterate an empty list

    prev = $(currentItem).prev()
    if prev.length
      prevId = Spark.getDataContext(prev[0])._id
    else # Beginning of list or lost selection; Go to end of list
      prevId = Spark.getDataContext(@tmplInst.find(".-autocomplete-item:last-child"))._id
    Session.set("-autocomplete-id", prevId)

  # Replace the appropriate region
  replace: (replacement) ->
    startpos = @getCursorPosition() # @$element.getCursorPosition()
    fullStuff = @getText()
    val = fullStuff.substring(0, startpos)

    replacement = @rules[@matched].token + replacement
    newClass = '-autocomplete-new-link'
    link = '<a href="/search/' + encodeURIComponent(replacement) + '" class="' + newClass + '">' + replacement + '</a>'
    val = val.replace(@expressions[@matched], "$1" + link)
    posfix = fullStuff.substring(startpos, fullStuff.length)
    separator = (if posfix.match(/^\s/) then "" else " ")
    finalFight = val + separator + posfix
    @setText finalFight
    range = document.createRange()
    range.setStartAfter(@$element.find('.' + newClass).removeClass(newClass).get(0))
    sel = window.getSelection()
    sel.removeAllRanges()
    sel.addRange(range)

  hideList: ->
    @matched = -1
    @ruleDep.changed()

  getText: ->
    if @element.hasAttribute('contenteditable')
      @$element.html()
    else
      @$element.val() || @$element.text()

  setText: (text) ->
    if @$element.is("input,textarea")
      @$element.val(text)
    else
      @$element.html(text)

  ###
    Reactive/rendering functions
  ###
  ruleMatched: ->
    @ruleDep.depend()
    @matched >= 0

  filteredList: ->
    @ruleDep.depend() # optional as long as we use filterDep, cause list will always get re-rendered
    @filterDep.depend()
    return null if @matched is -1

    rule = @rules[@matched]

    args = {}
    args[rule.field] =
      $regex: @filter # MIND BLOWN!
      $options: "i"

    return rule.collection.find(args, {limit: @limit})

  # This doesn't need to be reactive because list already changes reactively
  # and will cause all of the items to re-render anyway
  currentTemplate: -> @rules[@matched].template

  getMenuPositioning: ->
    html = @getText()
    startOffset = window.getSelection().getRangeAt(0).startOffset

    newHtml = [
      html.slice(0, @afterTokenPosition)
      '<span class="-autocomplete-after-token"></span>'
      html.slice(@afterTokenPosition)
    ].join('')

    @$element.html(newHtml)
    $afterToken = @$element.find('.-autocomplete-after-token')
    position = $afterToken.position()

    parentNode = $afterToken.get(0).parentNode
    $afterToken.remove()
    @element.normalize()
    range = document.createRange()
    range.setStart(parentNode.firstChild, startOffset)
    sel = window.getSelection()
    sel.removeAllRanges()
    sel.addRange(range)

    if @position is "top"
      # Do some additional calculation to position menu from bottom
      return {
        left: position.left
        bottom: @$element.offsetParent().outerHeight() - position.top
      }
    else
      return {
        left: position.left
        top: position.top
      }

  getCursorPosition: () ->
    caretPosition = 0
    if window.getSelection && window.getSelection().getRangeAt
      range = window.getSelection().getRangeAt(0)
      caretPosition = range.startOffset

      container = range.startContainer
      openTagLength = container.parentNode.outerHTML.indexOf(container.data)
      if openTagLength > 0
        caretPosition += openTagLength

      currentNode = window.getSelection().focusNode
      if currentNode isnt @element
        loop
          parentNode = currentNode.parentNode
          childNodes = parentNode.childNodes
          for i in [0..childNodes.length]
            if childNodes[i] is currentNode
              break
            if childNodes[i].outerHTML
              caretPosition += childNodes[i].outerHTML.length
            else if childNodes[i].nodeType == 3
              caretPosition += childNodes[i].textContent.length
          currentNode = parentNode
          break if parentNode is @element
    caretPosition
