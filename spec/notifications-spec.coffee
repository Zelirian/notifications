$ = require 'jquery'
fs = require 'fs-plus'
path = require 'path'
temp = require('temp').track()
{Notification} = require 'atom'
NotificationElement = require '../lib/notification-element'
NotificationIssue = require '../lib/notification-issue'

describe "Notifications", ->
  [workspaceElement, activationPromise] = []

  beforeEach ->
    workspaceElement = atom.views.getView(atom.workspace)
    atom.notifications.clear()
    activationPromise = atom.packages.activatePackage('notifications')

    waitsForPromise ->
      activationPromise

  describe "when the package is activated", ->
    it "attaches an atom-notifications element to the dom", ->
      expect(workspaceElement.querySelector('atom-notifications')).toBeDefined()

  describe "when there are notifications before activation", ->
    beforeEach ->
      atom.packages.deactivatePackage('notifications')

    it "displays all non displayed notifications", ->
      warning = new Notification('warning', 'Un-displayed warning')
      error = new Notification('error', 'Displayed error')
      error.setDisplayed(true)

      atom.notifications.addNotification(error)
      atom.notifications.addNotification(warning)

      activationPromise = atom.packages.activatePackage('notifications')
      waitsForPromise ->
        activationPromise

      runs ->
        notificationContainer = workspaceElement.querySelector('atom-notifications')
        notification = notificationContainer.querySelector('atom-notification.warning')
        expect(notification).toExist()
        notification = notificationContainer.querySelector('atom-notification.error')
        expect(notification).not.toExist()

  describe "when notifications are added to atom.notifications", ->
    notificationContainer = null
    beforeEach ->
      enableInitNotification = atom.notifications.addSuccess('A message to trigger initialization', dismissable: true)
      enableInitNotification.dismiss()
      advanceClock(NotificationElement::visibilityDuration)
      advanceClock(NotificationElement::animationDuration)

      notificationContainer = workspaceElement.querySelector('atom-notifications')
      jasmine.attachToDOM(workspaceElement)

      spyOn($, 'ajax')

    it "adds an atom-notification element to the container with a class corresponding to the type", ->
      expect(notificationContainer.childNodes.length).toBe 0

      atom.notifications.addSuccess('A message')
      notification = notificationContainer.querySelector('atom-notification.success')
      expect(notificationContainer.childNodes.length).toBe 1
      expect(notification).toHaveClass 'success'
      expect(notification.querySelector('.message').textContent.trim()).toBe 'A message'
      expect(notification.querySelector('.meta')).not.toBeVisible()

      atom.notifications.addInfo('A message')
      expect(notificationContainer.childNodes.length).toBe 2
      expect(notificationContainer.querySelector('atom-notification.info')).toBeDefined()

      atom.notifications.addWarning('A message')
      expect(notificationContainer.childNodes.length).toBe 3
      expect(notificationContainer.querySelector('atom-notification.warning')).toBeDefined()

      atom.notifications.addError('A message')
      expect(notificationContainer.childNodes.length).toBe 4
      expect(notificationContainer.querySelector('atom-notification.error')).toBeDefined()

      atom.notifications.addFatalError('A message')
      expect(notificationContainer.childNodes.length).toBe 5
      expect(notificationContainer.querySelector('atom-notification.fatal')).toBeDefined()

    it "displays notification with a detail when a detail is specified", ->
      atom.notifications.addInfo('A message', detail: 'Some detail')
      notification = notificationContainer.childNodes[0]
      expect(notification.querySelector('.detail').textContent).toContain 'Some detail'

      atom.notifications.addInfo('A message', detail: null)
      notification = notificationContainer.childNodes[1]
      expect(notification.querySelector('.detail')).not.toBeVisible()

      atom.notifications.addInfo('A message', detail: 1)
      notification = notificationContainer.childNodes[2]
      expect(notification.querySelector('.detail').textContent).toContain '1'

      atom.notifications.addInfo('A message', detail: {something: 'ok'})
      notification = notificationContainer.childNodes[3]
      expect(notification.querySelector('.detail').textContent).toContain 'Object'

      atom.notifications.addInfo('A message', detail: ['cats', 'ok'])
      notification = notificationContainer.childNodes[4]
      expect(notification.querySelector('.detail').textContent).toContain 'cats,ok'

    describe "when a dismissable notification is added", ->
      it "is removed when Notification::dismiss() is called", ->
        notification = atom.notifications.addSuccess('A message', dismissable: true)
        notificationElement = notificationContainer.querySelector('atom-notification.success')

        expect(notificationContainer.childNodes.length).toBe 1

        notification.dismiss()

        advanceClock(NotificationElement::visibilityDuration)
        expect(notificationElement).toHaveClass 'remove'

        advanceClock(NotificationElement::animationDuration)
        expect(notificationContainer.childNodes.length).toBe 0

      it "is removed when the close icon is clicked", ->
        jasmine.attachToDOM(workspaceElement)

        waitsForPromise ->
          atom.workspace.open()

        runs ->
          notification = atom.notifications.addSuccess('A message', dismissable: true)
          notificationElement = notificationContainer.querySelector('atom-notification.success')

          expect(notificationContainer.childNodes.length).toBe 1

          notificationElement.focus()
          notificationElement.querySelector('.close.icon').click()

          advanceClock(NotificationElement::visibilityDuration)
          expect(notificationElement).toHaveClass 'remove'

          advanceClock(NotificationElement::animationDuration)
          expect(notificationContainer.childNodes.length).toBe 0

      it "is removed when core:cancel is triggered", ->
        notification = atom.notifications.addSuccess('A message', dismissable: true)
        notificationElement = notificationContainer.querySelector('atom-notification.success')

        expect(notificationContainer.childNodes.length).toBe 1

        atom.commands.dispatch(workspaceElement, 'core:cancel')

        advanceClock(NotificationElement::visibilityDuration * 3)
        expect(notificationElement).toHaveClass 'remove'

        advanceClock(NotificationElement::animationDuration * 3)
        expect(notificationContainer.childNodes.length).toBe 0

      it "focuses the active pane only if the dismissed notification has focus", ->
        jasmine.attachToDOM(workspaceElement)

        waitsForPromise ->
          atom.workspace.open()

        runs ->
          notification1 = atom.notifications.addSuccess('First message', dismissable: true)
          notification2 = atom.notifications.addError('Second message', dismissable: true)
          notificationElement1 = notificationContainer.querySelector('atom-notification.success')
          notificationElement2 = notificationContainer.querySelector('atom-notification.error')

          expect(notificationContainer.childNodes.length).toBe 2

          notificationElement2.focus()

          notification1.dismiss()

          advanceClock(NotificationElement::visibilityDuration)
          advanceClock(NotificationElement::animationDuration)
          expect(notificationContainer.childNodes.length).toBe 1
          expect(notificationElement2).toHaveFocus()

          notificationElement2.querySelector('.close.icon').click()

          advanceClock(NotificationElement::visibilityDuration)
          advanceClock(NotificationElement::animationDuration)
          expect(notificationContainer.childNodes.length).toBe 0
          expect(atom.views.getView(atom.workspace.getActiveTextEditor())).toHaveFocus()

    describe "when an autoclose notification is added", ->
      it "closes and removes the message after a given amount of time", ->
        atom.notifications.addSuccess('A message')
        notification = notificationContainer.querySelector('atom-notification.success')
        expect(notification).not.toHaveClass 'remove'

        advanceClock(NotificationElement::visibilityDuration)
        expect(notification).toHaveClass 'remove'
        expect(notificationContainer.childNodes.length).toBe 1

        advanceClock(NotificationElement::animationDuration)
        expect(notificationContainer.childNodes.length).toBe 0

    describe "when the `description` option is used", ->
      it "displays the description text in the .description element", ->
        atom.notifications.addSuccess('A message', description: 'This is [a link](http://atom.io)')
        notification = notificationContainer.querySelector('atom-notification.success')
        expect(notification).toHaveClass('has-description')
        expect(notification.querySelector('.meta')).toBeVisible()
        expect(notification.querySelector('.description').textContent.trim()).toBe 'This is a link'
        expect(notification.querySelector('.description a').href).toBe 'http://atom.io/'

    describe "when the `buttons` options is used", ->
      it "displays the buttons in the .description element", ->
        clicked = []
        atom.notifications.addSuccess 'A message',
          buttons: [{
            text: 'Button One'
            className: 'btn-one'
            onDidClick: -> clicked.push 'one'
          }, {
            text: 'Button Two'
            className: 'btn-two'
            onDidClick: -> clicked.push 'two'
          }]

        notification = notificationContainer.querySelector('atom-notification.success')
        expect(notification).toHaveClass('has-buttons')
        expect(notification.querySelector('.meta')).toBeVisible()

        btnOne = notification.querySelector('.btn-one')
        btnTwo = notification.querySelector('.btn-two')

        expect(btnOne).toHaveClass 'btn-success'
        expect(btnOne.textContent).toBe 'Button One'
        expect(btnTwo).toHaveClass 'btn-success'
        expect(btnTwo.textContent).toBe 'Button Two'

        btnTwo.click()
        btnOne.click()

        expect(clicked).toEqual ['two', 'one']

    describe "when an exception is thrown", ->
      [notificationContainer, fatalError, issueTitle, issueBody] = []
      describe "when the editor is in dev mode", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn true
          generateException()
          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

        it "does not display a notification", ->
          expect(notificationContainer.childNodes.length).toBe 0
          expect(fatalError).toBe null

      describe "when the exception has no core or package paths in the stack trace", ->
        it "does not display a notification", ->
          atom.notifications.clear()
          spyOn(atom, 'inDevMode').andReturn false
          handler = jasmine.createSpy('onWillThrowErrorHandler')
          atom.onWillThrowError(handler)
          fs.readFile(__dirname)

          waitsFor ->
            handler.callCount is 1

          runs ->
            expect(atom.notifications.getNotifications().length).toBe 0

      describe "when there are multiple packages in the stack trace", ->
        beforeEach ->
          stack = """
            TypeError: undefined is not a function
              at Object.module.exports.Pane.promptToSaveItem [as defaultSavePrompt] (/Applications/Atom.app/Contents/Resources/app/src/pane.js:490:23)
              at Pane.promptToSaveItem (/Users/someguy/.atom/packages/save-session/lib/save-prompt.coffee:21:15)
              at Pane.module.exports.Pane.destroyItem (/Applications/Atom.app/Contents/Resources/app/src/pane.js:442:18)
              at HTMLDivElement.<anonymous> (/Applications/Atom.app/Contents/Resources/app/node_modules/tabs/lib/tab-bar-view.js:174:22)
              at space-pen-ul.jQuery.event.dispatch (/Applications/Atom.app/Contents/Resources/app/node_modules/archive-view/node_modules/atom-space-pen-views/node_modules/space-pen/vendor/jquery.js:4676:9)
              at space-pen-ul.elemData.handle (/Applications/Atom.app/Contents/Resources/app/node_modules/archive-view/node_modules/atom-space-pen-views/node_modules/space-pen/vendor/jquery.js:4360:46)
          """
          detail = 'ok'

          atom.notifications.addFatalError('TypeError: undefined', {detail, stack})
          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

          spyOn(require('fs'), 'realpathSync').andCallFake (p) -> p
          spyOn(fatalError.issue, 'getPackagePathsByPackageName').andCallFake ->
            'save-session': '/Users/someguy/.atom/packages/save-session'
            'tabs': '/Applications/Atom.app/Contents/Resources/app/node_modules/tabs'

        it "chooses the first package in the trace", ->
          expect(fatalError.issue.getPackageName()).toBe 'save-session'

      describe "when an exception is thrown from a package", ->
        beforeEach ->
          issueTitle = null
          issueBody = null
          spyOn(atom, 'inDevMode').andReturn false
          generateFakeAjaxResponses()
          generateException()
          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

        it "displays a fatal error with the package name in the error", ->
          waitsForPromise ->
            fatalError.getRenderPromise().then ->
              issueTitle = fatalError.issue.getIssueTitle()
              issueBody = fatalError.issue.issueBody

          runs ->
            expect(notificationContainer.childNodes.length).toBe 1
            expect(fatalError).toHaveClass 'has-close'
            expect(fatalError.innerHTML).toContain 'ReferenceError: a is not defined'
            expect(fatalError.innerHTML).toContain "<a href=\"https://github.com/atom/notifications\">notifications package</a>"
            expect(fatalError.issue.getPackageName()).toBe 'notifications'

            button = fatalError.querySelector('.btn')
            expect(button.textContent).toContain 'Create issue on the notifications package'
            expect(button.getAttribute('href')).toContain 'is.gd/cats'

            expect(issueTitle).toContain '$ATOM_HOME'
            expect(issueTitle).not.toContain process.env.ATOM_HOME
            expect(issueBody).toMatch /Atom Version\*\*: [0-9].[0-9]+.[0-9]+/ig
            expect(issueBody).not.toMatch /Unknown/ig
            expect(issueBody).toContain 'ReferenceError: a is not defined'
            expect(issueBody).toContain 'Thrown From**: [notifications](https://github.com/atom/notifications) package, v'
            expect(issueBody).toContain '# User'

            # FIXME: this doesnt work on the test server. `apm ls` is not working for some reason.
            # expect(issueBody).toContain 'notifications, v'

        it "contains core and notifications config values", ->
          atom.config.set('notifications.something', 10)
          waitsForPromise ->
            fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

          runs ->
            expect(issueBody).toContain '"core":'
            expect(issueBody).toContain '"notifications":'
            expect(issueBody).not.toContain '"editor":'

      describe "when an exception is thrown from a linked package", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false
          generateFakeAjaxResponses()

          packagesDir = path.join(temp.mkdirSync('atom-packages-'), '.atom', 'packages')
          atom.packages.packageDirPaths.push(packagesDir)
          packageDir = path.join(packagesDir, '..', '..', 'github', 'linked-package')
          fs.makeTreeSync path.dirname(path.join(packagesDir, 'linked-package'))
          fs.symlinkSync(packageDir, path.join(packagesDir, 'linked-package'), 'junction')
          fs.writeFileSync path.join(packageDir, 'package.json'), """
            {
              "name": "linked-package",
              "version": "1.0.0",
              "repository": "https://github.com/atom/notifications"
            }
          """
          atom.packages.enablePackage('linked-package')

          stack = """
            ReferenceError: path is not defined
              at Object.module.exports.LinkedPackage.wow (#{path.join(fs.realpathSync(packageDir), 'linked-package.coffee')}:29:15)
              at atom-workspace.subscriptions.add.atom.commands.add.linked-package:wow (#{path.join(packageDir, 'linked-package.coffee')}:18:102)
              at CommandRegistry.module.exports.CommandRegistry.handleCommandEvent (/Applications/Atom.app/Contents/Resources/app/src/command-registry.js:238:29)
              at /Applications/Atom.app/Contents/Resources/app/src/command-registry.js:3:61
              at CommandPaletteView.module.exports.CommandPaletteView.confirmed (/Applications/Atom.app/Contents/Resources/app/node_modules/command-palette/lib/command-palette-view.js:159:32)
          """
          detail = "At #{path.join(packageDir, 'linked-package.coffee')}:41"
          message = "Uncaught ReferenceError: path is not defined"
          atom.notifications.addFatalError(message, {stack, detail, dismissable: true})
          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

        it "displays a fatal error with the package name in the error", ->
          waitsForPromise ->
            fatalError.getRenderPromise()

          runs ->
            expect(notificationContainer.childNodes.length).toBe 1
            expect(fatalError).toHaveClass 'has-close'
            expect(fatalError.innerHTML).toContain "Uncaught ReferenceError: path is not defined"
            expect(fatalError.innerHTML).toContain "<a href=\"https://github.com/atom/notifications\">linked-package package</a>"
            expect(fatalError.issue.getPackageName()).toBe 'linked-package'

      describe "when an exception is thrown from an unloaded package", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false

          generateFakeAjaxResponses()

          packagesDir = temp.mkdirSync('atom-packages-')
          atom.packages.packageDirPaths.push(path.join(packagesDir, '.atom', 'packages'))
          packageDir = path.join(packagesDir, '.atom', 'packages', 'unloaded')
          fs.writeFileSync path.join(packageDir, 'package.json'), """
            {
              "name": "unloaded",
              "version": "1.0.0",
              "repository": "https://github.com/atom/notifications"
            }
          """

          stack = "Error\n  at #{path.join(packageDir, 'index.js')}:1:1"
          detail = 'ReferenceError: unloaded error'
          message = "Error"
          atom.notifications.addFatalError(message, {stack, detail, dismissable: true})
          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

        it "displays a fatal error with the package name in the error", ->
          waitsForPromise ->
            fatalError.getRenderPromise()

          runs ->
            expect(notificationContainer.childNodes.length).toBe 1
            expect(fatalError).toHaveClass 'has-close'
            expect(fatalError.innerHTML).toContain 'ReferenceError: unloaded error'
            expect(fatalError.innerHTML).toContain "<a href=\"https://github.com/atom/notifications\">unloaded package</a>"
            expect(fatalError.issue.getPackageName()).toBe 'unloaded'

      describe "when an exception is thrown from a package trying to load", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false
          generateFakeAjaxResponses()

          packagesDir = temp.mkdirSync('atom-packages-')
          atom.packages.packageDirPaths.push(path.join(packagesDir, '.atom', 'packages'))
          packageDir = path.join(packagesDir, '.atom', 'packages', 'broken-load')
          fs.writeFileSync path.join(packageDir, 'package.json'), """
            {
              "name": "broken-load",
              "version": "1.0.0",
              "repository": "https://github.com/atom/notifications"
            }
          """

          stack = "TypeError: Cannot read property 'prototype' of undefined\n  at __extends (<anonymous>:1:1)\n  at Object.defineProperty.value [as .coffee] (/Applications/Atom.app/Contents/Resources/app.asar/src/compile-cache.js:169:21)"
          detail = "TypeError: Cannot read property 'prototype' of undefined"
          message = "Failed to load the broken-load package"
          atom.notifications.addFatalError(message, {stack, detail, packageName: 'broken-load', dismissable: true})
          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

        it "displays a fatal error with the package name in the error", ->
          waitsForPromise ->
            fatalError.getRenderPromise()

          runs ->
            expect(notificationContainer.childNodes.length).toBe 1
            expect(fatalError).toHaveClass 'has-close'
            expect(fatalError.innerHTML).toContain "TypeError: Cannot read property 'prototype' of undefined"
            expect(fatalError.innerHTML).toContain "<a href=\"https://github.com/atom/notifications\">broken-load package</a>"
            expect(fatalError.issue.getPackageName()).toBe 'broken-load'

      describe "when an exception is thrown from a package trying to load a grammar", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false
          generateFakeAjaxResponses()

          packagesDir = temp.mkdirSync('atom-packages-')
          atom.packages.packageDirPaths.push(path.join(packagesDir, '.atom', 'packages'))
          packageDir = path.join(packagesDir, '.atom', 'packages', 'language-broken-grammar')
          fs.writeFileSync path.join(packageDir, 'package.json'), """
            {
              "name": "language-broken-grammar",
              "version": "1.0.0",
              "repository": "https://github.com/atom/notifications"
            }
          """

          stack = """
            Unexpected string
              at nodeTransforms.Literal (/usr/share/atom/resources/app/node_modules/season/node_modules/cson-parser/lib/parse.js:100:15)
              at #{path.join('packageDir', 'grammars', 'broken-grammar.cson')}:1:1
          """
          detail = """
            At Syntax error on line 241, column 18: evalmachine.<anonymous>:1
            "#\\{" "end": "\\}"
                   ^^^^^
            Unexpected string in #{path.join('packageDir', 'grammars', 'broken-grammar.cson')}

            SyntaxError: Syntax error on line 241, column 18: evalmachine.<anonymous>:1
            "#\\{" "end": "\\}"
                   ^^^^^
          """
          message = "Failed to load a language-broken-grammar package grammar"
          atom.notifications.addFatalError(message, {stack, detail, packageName: 'language-broken-grammar', dismissable: true})
          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

        it "displays a fatal error with the package name in the error", ->
          waitsForPromise ->
            fatalError.getRenderPromise()

          runs ->
            expect(notificationContainer.childNodes.length).toBe 1
            expect(fatalError).toHaveClass 'has-close'
            expect(fatalError.innerHTML).toContain "Failed to load a language-broken-grammar package grammar"
            expect(fatalError.innerHTML).toContain "<a href=\"https://github.com/atom/notifications\">language-broken-grammar package</a>"
            expect(fatalError.issue.getPackageName()).toBe 'language-broken-grammar'

      describe "when an exception is thrown from a package trying to activate", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false
          generateFakeAjaxResponses()

          packagesDir = temp.mkdirSync('atom-packages-')
          atom.packages.packageDirPaths.push(path.join(packagesDir, '.atom', 'packages'))
          packageDir = path.join(packagesDir, '.atom', 'packages', 'broken-activation')
          fs.writeFileSync path.join(packageDir, 'package.json'), """
            {
              "name": "broken-activation",
              "version": "1.0.0",
              "repository": "https://github.com/atom/notifications"
            }
          """

          stack = "TypeError: Cannot read property 'command' of undefined\n  at Object.module.exports.activate (<anonymous>:7:23)\n  at Package.module.exports.Package.activateNow (/Applications/Atom.app/Contents/Resources/app.asar/src/package.js:232:19)"
          detail = "TypeError: Cannot read property 'command' of undefined"
          message = "Failed to activate the broken-activation package"
          atom.notifications.addFatalError(message, {stack, detail, packageName: 'broken-activation', dismissable: true})
          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

        it "displays a fatal error with the package name in the error", ->
          waitsForPromise ->
            fatalError.getRenderPromise()

          runs ->
            expect(notificationContainer.childNodes.length).toBe 1
            expect(fatalError).toHaveClass 'has-close'
            expect(fatalError.innerHTML).toContain "TypeError: Cannot read property 'command' of undefined"
            expect(fatalError.innerHTML).toContain "<a href=\"https://github.com/atom/notifications\">broken-activation package</a>"
            expect(fatalError.issue.getPackageName()).toBe 'broken-activation'

      describe "when an exception is thrown from a package without a trace, but with a URL", ->
        beforeEach ->
          issueBody = null
          spyOn(atom, 'inDevMode').andReturn false
          generateFakeAjaxResponses()
          try
            a + 1
          catch e
            # Pull the file path from the stack
            filePath = e.stack.split('\n')[1].match(/\((.+?):\d+/)[1]
            window.onerror.call(window, e.toString(), filePath, 2, 3, message: e.toString(), stack: undefined)

          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')

        it "detects the package name from the URL", ->
          waitsForPromise -> fatalError.getRenderPromise()

          runs ->
            expect(fatalError.innerHTML).toContain 'ReferenceError: a is not defined'
            expect(fatalError.innerHTML).toContain "<a href=\"https://github.com/atom/notifications\">notifications package</a>"
            expect(fatalError.issue.getPackageName()).toBe 'notifications'

      describe "when an exception is thrown from core", ->
        beforeEach ->
          atom.commands.dispatch(workspaceElement, 'some-package:a-command')
          atom.commands.dispatch(workspaceElement, 'some-package:a-command')
          atom.commands.dispatch(workspaceElement, 'some-package:a-command')
          spyOn(atom, 'inDevMode').andReturn false
          generateFakeAjaxResponses()
          try
            a + 1
          catch e
            # Mung the stack so it looks like its from core
            e.stack = e.stack.replace(/notifications/g, 'core')
            window.onerror.call(window, e.toString(), '/dev/null', 2, 3, e)

          notificationContainer = workspaceElement.querySelector('atom-notifications')
          fatalError = notificationContainer.querySelector('atom-notification.fatal')
          waitsForPromise ->
            fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

        it "displays a fatal error with the package name in the error", ->
          expect(notificationContainer.childNodes.length).toBe 1
          expect(fatalError).toBeDefined()
          expect(fatalError).toHaveClass 'has-close'
          expect(fatalError.innerHTML).toContain 'ReferenceError: a is not defined'
          expect(fatalError.innerHTML).toContain 'bug in Atom'
          expect(fatalError.issue.getPackageName()).toBeUndefined()

          button = fatalError.querySelector('.btn')
          expect(button.textContent).toContain 'Create issue on atom/atom'
          expect(button.getAttribute('href')).toContain 'is.gd/cats'

          expect(issueBody).toContain 'ReferenceError: a is not defined'
          expect(issueBody).toContain '**Thrown From**: Atom Core'

        it "contains core and editor config values", ->
          expect(issueBody).toContain '"core":'
          expect(issueBody).toContain '"editor":'
          expect(issueBody).not.toContain '"notifications":'

        it "contains the commands that the user run in the issue body", ->
          expect(issueBody).toContain 'some-package:a-command'

        it "allows the user to toggle the stack trace", ->
          stackToggle = fatalError.querySelector('.stack-toggle')
          stackContainer = fatalError.querySelector('.stack-container')
          expect(stackToggle).toExist()
          expect(stackContainer.style.display).toBe 'none'

          stackToggle.click()
          expect(stackContainer.style.display).toBe 'block'

          stackToggle.click()
          expect(stackContainer.style.display).toBe 'none'

      describe "when the there is an error searching for the issue", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false
          generateFakeAjaxResponses(issuesErrorResponse: '403')
          generateException()
          fatalError = notificationContainer.querySelector('atom-notification.fatal')
          waitsForPromise ->
            fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

        it "asks the user to create an issue", ->
          button = fatalError.querySelector('.btn')
          fatalNotification = fatalError.querySelector('.fatal-notification')
          expect(button.textContent).toContain 'Create issue'
          expect(fatalNotification.textContent).toContain 'You can help by creating an issue'
          expect(button.getAttribute('href')).toContain 'is.gd/cats'

      describe "when the error has not been reported", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false

        describe "when the message is longer than 100 characters", ->
          message = "Uncaught Error: Cannot find module 'dialog'Error: Cannot find module 'dialog' at Function.Module._resolveFilename (module.js:351:15) at Function.Module._load (module.js:293:25) at Module.require (module.js:380:17) at EventEmitter.<anonymous> (/Applications/Atom.app/Contents/Resources/atom/browser/lib/rpc-server.js:128:79) at EventEmitter.emit (events.js:119:17) at EventEmitter.<anonymous> (/Applications/Atom.app/Contents/Resources/atom/browser/api/lib/web-contents.js:99:23) at EventEmitter.emit (events.js:119:17)"
          truncatedMessage = "Uncaught Error: Cannot find module 'dialog'Error: Cannot find module 'dialog' at Function.Module...."

          beforeEach ->
            generateFakeAjaxResponses()
            try
              a + 1
            catch e
              e.code = 'Error'
              e.message = message
              window.onerror.call(window, e.message, 'abc', 2, 3, e)

          it "truncates the issue title to 100 characters", ->
            fatalError = notificationContainer.querySelector('atom-notification.fatal')

            waitsForPromise ->
              fatalError.getRenderPromise()

            runs ->
              button = fatalError.querySelector('.btn')
              encodedMessage = encodeURI(truncatedMessage)
              expect(button.textContent).toContain 'Create issue'
              expect(button.getAttribute('href')).toContain 'is.gd/cats'

      describe "when the package is out of date", ->
        beforeEach ->
          installedVersion = '0.9.0'
          UserUtilities = require '../lib/user-utilities'
          spyOn(UserUtilities, 'getPackageVersion').andCallFake -> installedVersion
          spyOn(atom, 'inDevMode').andReturn false

        describe "when the package is a non-core package", ->
          beforeEach ->
            generateFakeAjaxResponses
              packageResponse:
                repository: url: 'https://github.com/someguy/somepackage'
                releases: latest: '0.10.0'
            spyOn(NotificationIssue.prototype, 'getPackageName').andCallFake -> "somepackage"
            spyOn(NotificationIssue.prototype, 'getRepoUrl').andCallFake -> "https://github.com/someguy/somepackage"
            generateException()
            fatalError = notificationContainer.querySelector('atom-notification.fatal')
            waitsForPromise ->
              fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

          it "asks the user to update their packages", ->
            fatalNotification = fatalError.querySelector('.fatal-notification')
            button = fatalError.querySelector('.btn')

            expect(button.textContent).toContain 'Check for package updates'
            expect(fatalNotification.textContent).toContain 'Upgrading to the latest'
            expect(button.getAttribute('href')).toBe '#'

        describe "when the package is an atom-owned non-core package", ->
          beforeEach ->
            generateFakeAjaxResponses
              packageResponse:
                repository: url: 'https://github.com/atom/sort-lines'
                releases: latest: '0.10.0'
            spyOn(NotificationIssue.prototype, 'getPackageName').andCallFake -> "sort-lines"
            spyOn(NotificationIssue.prototype, 'getRepoUrl').andCallFake -> "https://github.com/atom/sort-lines"
            generateException()
            fatalError = notificationContainer.querySelector('atom-notification.fatal')

            waitsForPromise ->
              fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

          it "asks the user to update their packages", ->
            fatalNotification = fatalError.querySelector('.fatal-notification')
            button = fatalError.querySelector('.btn')

            expect(button.textContent).toContain 'Check for package updates'
            expect(fatalNotification.textContent).toContain 'Upgrading to the latest'
            expect(button.getAttribute('href')).toBe '#'

        describe "when the package is a core package", ->
          beforeEach ->
            generateFakeAjaxResponses
              packageResponse:
                repository: url: 'https://github.com/atom/notifications'
                releases: latest: '0.11.0'

          describe "when the locally installed version is lower than Atom's version", ->
            beforeEach ->
              versionShippedWithAtom = '0.10.0'
              UserUtilities = require '../lib/user-utilities'
              spyOn(UserUtilities, 'getPackageVersionShippedWithAtom').andCallFake -> versionShippedWithAtom

              generateException()
              fatalError = notificationContainer.querySelector('atom-notification.fatal')
              waitsForPromise ->
                fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

            it "doesn't show the Create Issue button", ->
              button = fatalError.querySelector('.btn-issue')
              expect(button).not.toExist()

            it "tells the user that the package is a locally installed core package and out of date", ->
              fatalNotification = fatalError.querySelector('.fatal-notification')
              expect(fatalNotification.textContent).toContain 'Locally installed core Atom package'
              expect(fatalNotification.textContent).toContain 'is out of date'

          describe "when the locally installed version matches Atom's version", ->
            beforeEach ->
              versionShippedWithAtom = '0.9.0'
              UserUtilities = require '../lib/user-utilities'
              spyOn(UserUtilities, 'getPackageVersionShippedWithAtom').andCallFake -> versionShippedWithAtom

              generateException()
              fatalError = notificationContainer.querySelector('atom-notification.fatal')
              waitsForPromise ->
                fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

            it "ignores the out of date package because they cant upgrade it without upgrading atom", ->
              fatalError = notificationContainer.querySelector('atom-notification.fatal')
              button = fatalError.querySelector('.btn')
              expect(button.textContent).toContain 'Create issue'

      describe "when Atom is out of date", ->
        beforeEach ->
          installedVersion = '0.179.0'
          spyOn(atom, 'getVersion').andCallFake -> installedVersion
          spyOn(atom, 'inDevMode').andReturn false

          generateFakeAjaxResponses
            atomResponse:
              name: '0.180.0'

          generateException()

          fatalError = notificationContainer.querySelector('atom-notification.fatal')
          waitsForPromise ->
            fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

        it "doesn't show the Create Issue button", ->
          button = fatalError.querySelector('.btn-issue')
          expect(button).not.toExist()

        it "tells the user that Atom is out of date", ->
          fatalNotification = fatalError.querySelector('.fatal-notification')
          expect(fatalNotification.textContent).toContain 'Atom is out of date'

        it "provides a link to the latest released version", ->
          fatalNotification = fatalError.querySelector('.fatal-notification')
          expect(fatalNotification.innerHTML).toContain '<a href="https://github.com/atom/atom/releases/tag/v0.180.0">latest version</a>'

      describe "when the error has been reported", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false

        describe "when the issue is open", ->
          beforeEach ->
            generateFakeAjaxResponses
              issuesResponse:
                items: [
                  {
                    title: 'ReferenceError: a is not defined in $ATOM_HOME/somewhere'
                    html_url: 'http://url.com/ok'
                    state: 'open'
                  }
                ]
            generateException()
            fatalError = notificationContainer.querySelector('atom-notification.fatal')
            waitsForPromise ->
              fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

          it "shows the user a view issue button", ->
            fatalNotification = fatalError.querySelector('.fatal-notification')
            button = fatalError.querySelector('.btn')
            expect(button.textContent).toContain 'View Issue'
            expect(button.getAttribute('href')).toBe 'http://url.com/ok'
            expect(fatalNotification.textContent).toContain 'already been reported'
            expect($.ajax.calls[0].args[0]).toContain 'atom/notifications'

        describe "when the issue is closed", ->
          beforeEach ->
            generateFakeAjaxResponses
              issuesResponse:
                items: [
                  {
                    title: 'ReferenceError: a is not defined in $ATOM_HOME/somewhere'
                    html_url: 'http://url.com/closed'
                    state: 'closed'
                  }
                ]
            generateException()
            fatalError = notificationContainer.querySelector('atom-notification.fatal')
            waitsForPromise ->
              fatalError.getRenderPromise().then -> issueBody = fatalError.issue.issueBody

          it "shows the user a view issue button", ->
            button = fatalError.querySelector('.btn')
            expect(button.textContent).toContain 'View Issue'
            expect(button.getAttribute('href')).toBe 'http://url.com/closed'

      describe "when a BufferedProcessError is thrown", ->
        it "adds an error to the notifications", ->
          expect(notificationContainer.querySelector('atom-notification.error')).not.toExist()

          window.onerror('Uncaught BufferedProcessError: Failed to spawn command `bad-command`', 'abc', 2, 3, {name: 'BufferedProcessError'})

          error = notificationContainer.querySelector('atom-notification.error')
          expect(error).toExist()
          expect(error.innerHTML).toContain 'Failed to spawn command'
          expect(error.innerHTML).not.toContain 'BufferedProcessError'

      describe "when a spawn ENOENT error is thrown", ->
        beforeEach ->
          spyOn(atom, 'inDevMode').andReturn false

        describe "when the binary has no path", ->
          beforeEach ->
            error = new Error('Error: spawn some_binary ENOENT')
            error.code = 'ENOENT'
            window.onerror.call(window, error.message, 'abc', 2, 3, error)

          it "displays a dismissable error without the stack trace", ->
            notificationContainer = workspaceElement.querySelector('atom-notifications')
            error = notificationContainer.querySelector('atom-notification.error')
            expect(error.textContent).toContain "'some_binary' could not be spawned"

        describe "when the binary has /atom in the path", ->
          beforeEach ->
            try
              a + 1
            catch e
              e.code = 'ENOENT'
              message = 'Error: spawn /opt/atom/Atom Helper (deleted) ENOENT'
              window.onerror.call(window, message, 'abc', 2, 3, e)

          it "displays a fatal error", ->
            notificationContainer = workspaceElement.querySelector('atom-notifications')
            error = notificationContainer.querySelector('atom-notification.fatal')
            expect(error).toExist()

generateException = ->
  try
    a + 1
  catch e
    errMsg = e.toString() + ' in ' + process.env.ATOM_HOME + '/somewhere'
    window.onerror.call(window, errMsg, '/dev/null', 2, 3, e)

# shortenerResponse
# packageResponse
# issuesResponse
generateFakeAjaxResponses = (options) ->
  $.ajax.andCallFake (url, settings) ->
    if url.indexOf('is.gd') > -1
      response = options?.shortenerResponse ? 'http://is.gd/cats'
      settings.success(response)
    else if url.indexOf('atom.io/api/packages') > -1
      response = options?.packageResponse ? {
        repository: url: 'https://github.com/atom/notifications'
        releases: latest: '0.0.0'
      }
      settings.success(response)
    else if url.indexOf('atom.io/api/updates') > -1
      response = options?.atomResponse ? {
        name: atom.getVersion()
      }
      settings.success(response)
    else
      if options?.issuesErrorResponse?
        settings.error?({}, options.issuesErrorResponse, null)
      else
        response = options?.issuesResponse ? {
          items: []
        }
        settings.success(response)

window.waitsForPromise = (fn) ->
  promise = fn()
  window.waitsFor 5000, (moveOn) ->
    promise.then(moveOn)
    promise.catch (error) ->
      jasmine.getEnv().currentSpec.fail("Expected promise to be resolved, but it was rejected with #{jasmine.pp(error)}")
      moveOn()
