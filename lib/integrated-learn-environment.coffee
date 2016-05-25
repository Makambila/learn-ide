{CompositeDisposable} = require 'atom'
Terminal = require './models/terminal'
SyncedFS = require './models/synced-fs'
TerminalView = require './views/terminal'
SyncedFSView = require './views/synced-fs'
{EventEmitter} = require 'events'
ipc = require 'ipc'
screenshot = require('electron-screenshot')
LearnUpdater = require './models/learn-updater'

module.exports =
  config:
    oauthToken:
      type: 'string'
      title: 'OAuth Token'
      description: 'Your learn.co oauth token'
      default: "Paste your learn.co oauth token here"

  termViewState: null
  fsViewState: null
  subscriptions: null

  activate: (state) ->
    @oauthToken = atom.config.get('integrated-learn-environment.oauthToken')
    openPath = atom.blobStore.get('learnOpenUrl', 'learn-open-url-key')
    atom.blobStore.delete('learnOpenUrl')
    atom.blobStore.save()

    isTerminalWindow = atom.isTerminalWindow

    @term = new Terminal("wss://ile.learn.co:4463?token=" + @oauthToken, isTerminalWindow)
    @termView = new TerminalView(state, @term, openPath, isTerminalWindow)

    if isTerminalWindow
      document.getElementsByClassName('terminal-view-resize-handle')[0].setAttribute('style', 'display:none;')
      document.getElementsByClassName('inset-panel')[0].setAttribute('style', 'display:none;')
      document.getElementsByClassName('learn-terminal')[0].style.height = '448px'
      workspaceView = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceView, 'tree-view:toggle')

    @fs = new SyncedFS("wss://ile.learn.co:4464?token=" + @oauthToken, isTerminalWindow)
    @fsViewEmitter = new EventEmitter
    @fsView = new SyncedFSView(state, @fs, @fsViewEmitter, isTerminalWindow)

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-workspace', 'integrated-learn-environment:screenshot': =>
      screenshot(filename:"/Users/devin/Desktop/foo.png")
    @subscriptions.add atom.commands.add 'atom-workspace', 'integrated-learn-environment:toggleTerminal': =>
      @termView.toggle()
    @subscriptions.add atom.commands.add 'atom-workspace', 'integrated-learn-environment:reset': =>
      @term.term.write('\n\rReconnecting...\r')
      ipc.send 'reset-connection'
      ipc.send 'connection-state-request'
    @subscriptions.add atom.commands.add 'atom-workspace', 'application:update-ile': =>
      updater = new LearnUpdater
      updater.checkForUpdate()

    @passingIcon = 'http://i.imgbox.com/pAjW8tY1.png'
    @failingIcon = 'http://i.imgbox.com/vVZZG1Gx.png'

    ipc.send 'register-for-notifications', @oauthToken

    ipc.on 'remote-log', (msg) ->
      console.log(msg)

    ipc.on 'new-notification', (data) =>
      icon = if data.passing == 'true' then @passingIcon else @failingIcon

      notif = new Notification data.displayTitle,
        body: data.message
        icon: icon

      notif.onclick = ->
        notif.close()

    ipc.on 'in-app-notification', (notifData) =>
      atom.notifications['add' + notifData.type.charAt(0).toUpperCase() + notifData.type.slice(1)] notifData.message, {detail: notifData.detail, dismissable: notifData.dismissable}

    @fsViewEmitter.on 'toggleTerminal', (focus) =>
      @termView.toggle(focus)

    autoUpdater = new LearnUpdater(true)
    autoUpdater.checkForUpdate()

  deactivate: ->
    @termView = null
    @fsView = null
    @subscriptions.dispose()

    ipc.send 'deactivate-listener'

  consumeStatusBar: (statusBar) ->
    @statusBarTile = statusBar.addRightTile(item: @fsView, priority: 5000)

  serialize: ->
    termViewState: @termView.serialize()
    fsViewState: @fsView.serialize()
