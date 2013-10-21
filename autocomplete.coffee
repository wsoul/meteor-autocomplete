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
      selection = rangy.getSelection()
      if selection.isCollapsed and selection.rangeCount is 1
        startpos = @getCursorPosition() #@$element.getCursorPosition() # TODO: this doesn't seem to be correct on a focus
        html = @getText()
        val = html.substring(0, startpos)
        @tokenChanged = false
        console.log startpos, val
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

            parentNode = selection.focusNode.parentNode
            if startpos is @afterTokenPosition and parentNode.nodeName.toLowerCase() isnt 'a'
              @element.normalize()
              range = selection.getRangeAt(0)
              endOffset = range.startOffset + selection.focusNode.textContent.substring(range.startOffset).search(/($|\s)/)
              range.setStart(range.startContainer, range.startOffset - 1)
              range.setEnd(range.startContainer, endOffset)
              link = document.createElement('a')
              link.href = '/search/' + encodeURIComponent(range.toString())
              range.surroundContents(link)
              range.setStart(link.firstChild, 1)
              range.setEnd(link.firstChild, 1)
              selection.setSingleRange(range)
              @afterTokenPosition += @getCursorPosition() - startpos

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
    selection = rangy.getSelection()
    range = selection.getRangeAt(0)
    link = range.startContainer.parentNode
    if link.nodeName.toLowerCase() is 'a'
      replacement = @rules[@matched].token + replacement
      link.href = '/search/' + encodeURIComponent(replacement)
      link.innerText = replacement
      range.setStartAfter(link)
      selection.setSingleRange(range)

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
    selection = rangy.getSelection()
    range = selection.getRangeAt(0)
    startOffset = range.startOffset

    newHtml = [
      html.slice(0, @afterTokenPosition)
      '<span class="-autocomplete-after-token"></span>'
      html.slice(@afterTokenPosition)
    ].join('')

    @$element.html(newHtml)
    $afterToken = @$element.find('.-autocomplete-after-token')
    position = $afterToken.position()
    lineHeight = $afterToken.outerHeight()

    previousSibling = $afterToken.get(0).previousSibling
    $afterToken.remove()
    @element.normalize()
    range.setStart(previousSibling, startOffset)
    selection.setSingleRange(range)

    if @position is "top"
      # Do some additional calculation to position menu from bottom
      return {
        left: position.left
        bottom: @$element.offsetParent().outerHeight() - position.top
      }
    else
      return {
        left: position.left
        top: position.top + lineHeight
      }

  getCursorPosition: () ->
    caretPosition = 0
    range = rangy.getSelection().getRangeAt(0)
    textContent = range.startContainer.textContent
    caretPosition = range.startOffset + $('<span>').text(textContent).html().length - textContent.length

    currentNode = range.startContainer
    if currentNode isnt @element
      loop
        parentNode = currentNode.parentNode
        childNodes = parentNode.childNodes
        for childNode in childNodes
          if childNode is currentNode
            if childNode.outerHTML
              caretPosition += childNode.outerHTML.indexOf('>') + 1
            break
          else if childNode.outerHTML
            caretPosition += childNode.outerHTML.length
          else if childNode.nodeType == 3
            caretPosition += childNode.textContent.length
        currentNode = parentNode
        break if parentNode is @element
    caretPosition
