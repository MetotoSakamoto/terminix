/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.terminix.application;

import std.experimental.logger;
import std.format;
import std.path;
import std.variant;

import gio.ActionGroupIF;
import gio.ActionMapIF;
import gio.Menu;
import gio.MenuModel;
import gio.Settings : GSettings = Settings;
import gio.SimpleAction;

import glib.ShellUtils;
import glib.Variant : GVariant = Variant;
import glib.VariantType : GVariantType = VariantType;

import gtk.AboutDialog;
import gtk.Application;
import gtk.CheckButton;
import gtk.Dialog;
import gtk.Image;
import gtk.Label;
import gtk.LinkButton;
import gtk.Main;
import gtk.MessageDialog;
import gtk.Settings;
import gtk.Widget;
import gtk.Window;

import gx.gtk.actions;
import gx.gtk.util;
import gx.i18n.l10n;
import gx.terminix.appwindow;
import gx.terminix.cmdparams;
import gx.terminix.common;
import gx.terminix.constants;
import gx.terminix.preferences;
import gx.terminix.prefwindow;
import gx.terminix.profilewindow;

Terminix terminix;

/**
 * The GTK Application used by Terminix.
 */
class Terminix : Application {

private:

    enum ACTION_PREFIX = "app";

    enum ACTION_NEW_WINDOW = "new-window";
    enum ACTION_NEW_SESSION = "new-session";
    enum ACTION_ACTIVATE_SESSION = "activate-session";
    enum ACTION_PREFERENCES = "preferences";
    enum ACTION_ABOUT = "about";
    enum ACTION_QUIT = "quit";
    enum ACTION_COMMAND = "command";

    GSettings gsShortcuts;
    GSettings gsGeneral;

    CommandParameters cp;
    
    AppWindow[] appWindows;
    ProfileWindow[] profileWindows;
    PreferenceWindow preferenceWindow;
    
    bool warnedVTEConfigIssue = false;

    /**
     * Load and register binary resource file and add css files as providers
     */
    void loadResources() {
        //Load resources
        if (findResource(APPLICATION_RESOURCES, true)) {
            foreach (cssFile; APPLICATION_CSS_RESOURCES) {
                string cssURI = buildPath(APPLICATION_RESOURCE_ROOT, cssFile);
                if (!addCssProvider(cssURI, ProviderPriority.FALLBACK)) {
                    error(format("Could not load CSS %s", cssURI));
                }
            }
        }
    }

    /**
     * Installs the application menu. This is the menu that drops down in gnome-shell when you click the application
     * name next to Activities.
     * 
	 * This code adapted from grestful (https://github.com/Gert-dev/grestful)
     */
    void installAppMenu() {
        gsShortcuts = new GSettings(SETTINGS_PROFILE_KEY_BINDINGS_ID);
        Menu appMenu = new Menu();

        registerAction(this, ACTION_PREFIX, ACTION_ACTIVATE_SESSION, null, delegate(GVariant value, SimpleAction sa) {
            ulong l;
            string sessionUUID = value.getString(l);
            trace("activate-session triggered for session " ~ sessionUUID);
            foreach (window; appWindows) {
                if (window.activateSession(sessionUUID)) {
                    window.present();
                    break;
                }
            }
        }, new GVariantType("s"));

        registerActionWithSettings(this, ACTION_PREFIX, ACTION_NEW_SESSION, gsShortcuts, delegate(GVariant, SimpleAction) { onCreateNewSession(); });

        registerActionWithSettings(this, ACTION_PREFIX, ACTION_NEW_WINDOW, gsShortcuts, delegate(GVariant, SimpleAction) { onCreateNewWindow(); });

        registerActionWithSettings(this, ACTION_PREFIX, ACTION_PREFERENCES, gsShortcuts, delegate(GVariant, SimpleAction) { onShowPreferences(); });

        registerAction(this, ACTION_PREFIX, ACTION_ABOUT, null, delegate(GVariant, SimpleAction) { onShowAboutDialog(); });

        registerAction(this, ACTION_PREFIX, ACTION_QUIT, null, delegate(GVariant, SimpleAction) {
            quitTerminix();
        });

        Menu newSection = new Menu();
        newSection.append(_("New Session"), getActionDetailedName(ACTION_PREFIX, ACTION_NEW_SESSION));
        newSection.append(_("New Window"), getActionDetailedName(ACTION_PREFIX, ACTION_NEW_WINDOW));
        appMenu.appendSection(null, newSection);

        Menu prefSection = new Menu();
        prefSection.append(_("Preferences"), getActionDetailedName(ACTION_PREFIX, ACTION_PREFERENCES));
        appMenu.appendSection(null, prefSection);

        Menu otherSection = new Menu();
        otherSection.append(_("About"), getActionDetailedName(ACTION_PREFIX, ACTION_ABOUT));
        otherSection.append(_("Quit"), getActionDetailedName(ACTION_PREFIX, ACTION_QUIT));
        appMenu.appendSection(null, otherSection);

        this.setAppMenu(appMenu);
    }

    void onCreateNewSession() {
        AppWindow appWindow = cast(AppWindow) getActiveWindow();
        if (appWindow !is null)
            appWindow.createSession();
    }

    void onCreateNewWindow() {
        createAppWindow();
    }

    void onShowPreferences() {
        presentPreferences();
    }
    
    /**
     * Shows the about dialog.
     * 
	 * This code adapted from grestful (https://github.com/Gert-dev/grestful)
     */
    void onShowAboutDialog() {
        AboutDialog dialog;

        with (dialog = new AboutDialog()) {
            setTransientFor(getActiveWindow());
            setDestroyWithParent(true);
            setModal(true);

            setWrapLicense(true);
            setLogoIconName(null);
            setName(APPLICATION_NAME);
            setComments(APPLICATION_COMMENTS);
            setVersion(APPLICATION_VERSION);
            setCopyright(APPLICATION_COPYRIGHT);
            setAuthors(APPLICATION_AUTHORS.dup);
            setArtists(APPLICATION_ARTISTS.dup);
            setDocumenters(APPLICATION_DOCUMENTERS.dup);
            setTranslatorCredits(APPLICATION_TRANSLATORS);
            setLicense(APPLICATION_LICENSE);
            addCreditSection(_("Credits"), APPLICATION_CREDITS);

            addOnResponse(delegate(int responseId, Dialog sender) {
                if (responseId == ResponseType.CANCEL || responseId == ResponseType.DELETE_EVENT)
                    sender.hideOnDelete(); // Needed to make the window closable (and hide instead of be deleted).
            });

            present();
        }
    }
    
    void createAppWindow() {
        AppWindow window = new AppWindow(this);
        window.initialize();
        window.showAll();
    }

    void quitTerminix() {
        foreach(window; appWindows) {
            window.close();
        }
        foreach(window; profileWindows) {
            window.close();
        }
        if (preferenceWindow !is null) preferenceWindow.close();
    }

    void onAppActivate(GioApplication app) {
        trace("Activate App Signal");
        createAppWindow();
        cp.clear();
    }

    void onAppStartup(GioApplication app) {
        trace("Startup App Signal");
        loadResources();
        gsShortcuts = new GSettings(SETTINGS_PROFILE_KEY_BINDINGS_ID);
        gsShortcuts.addOnChanged(delegate(string key, Settings) {
            trace("Updating shortcut '" ~ keyToDetailedActionName(key) ~ "' to '" ~ gsShortcuts.getString(key) ~ "'");
            setAccelsForAction(keyToDetailedActionName(key), [gsShortcuts.getString(key)]);
            string[] values = getAccelsForAction(keyToDetailedActionName(key));
            foreach (value; values) {
                trace("Accel " ~ value ~ " for action " ~ keyToDetailedActionName(key));
            }
        });
        gsGeneral = new GSettings(SETTINGS_ID);
        gsGeneral.addOnChanged(delegate(string key, Settings) { applyPreferences(); });

        initProfileManager();
        applyPreferences();
        installAppMenu();
    }

    void onAppShutdown(GioApplication app) {
        trace("Quit App Signal");
        terminix = null;
    }

    void applyPreferences() {
        string theme = gsGeneral.getString(SETTINGS_THEME_VARIANT_KEY);
        if (theme == SETTINGS_THEME_VARIANT_DARK_VALUE || theme == SETTINGS_THEME_VARIANT_LIGHT_VALUE) { 
            Settings.getDefault().setProperty(GTK_APP_PREFER_DARK_THEME, (SETTINGS_THEME_VARIANT_DARK_VALUE == theme));
        } else {
            //While the code below works, gives some critical errors, for now
            //switching to Default from Dark/Light needs a restart
            /*
            //Need to reset property here when it is DEFAULT
            gobject.Value.Value value = new gobject.Value.Value(false);
            Settings.getDefault().getProperty(GTK_APP_PREFER_DARK_THEME, value);
            value.reset();
            Settings.getDefault().setProperty(GTK_APP_PREFER_DARK_THEME, value);
            */
        }
    }
    
    void executeCommand(GVariant value, SimpleAction sa) {
        //Clear command parameters at end of command
        //Only set them temporarily so if a terminal is created
        //as a result of the action it can inherit them. The
        //command line parameters are sent by the remote Application
        //and packed into the value parameter.
        scope (exit) {cp.clear();}
        ulong l;
        string command = value.getChildValue(0).getString(l);
        if (command.length == 0) {
            error("No command was received");
            return;
        }
        string terminalUUID = value.getChildValue(1).getString(l);
        if (terminalUUID.length == 0) {
            error("Terminal UUID was not sent for command, cannot resolve");
            return;
        }
        string cmdLine = value.getChildValue(2).getString(l);
        string[] args;
        ShellUtils.shellParseArgv(cmdLine, args);
        cp = CommandParameters(args);
        trace(format("Command Received, command=%s, terminalID=%s, cmdLine=%s", command, terminalUUID, cmdLine));
        //Get action name
        string prefix;
        string actionName;
        getActionNameFromKey(command, prefix, actionName);
        Widget widget = findWidgetForUUID(terminalUUID);
        while (widget !is null) {
            ActionGroupIF group = widget.getActionGroup(prefix);
            if (group !is null && group.hasAction(actionName)) {
                trace(format("Activating action for prefix=%s and action=%s", prefix, actionName));
                group.activateAction(actionName, null);
                return;    
            }
            widget = widget.getParent();
        }
        //Check if the action belongs to the app
        if (prefix == ACTION_PREFIX) {
            activateAction(actionName, null);
            return;
        }
        trace(format("Could not find action for prefix=%s and action=%s", prefix, actionName));
    }

public:

    this(CommandParameters cp) {
        super(APPLICATION_ID, ApplicationFlags.FLAGS_NONE);
        this.cp = cp;
        this.addOnActivate(&onAppActivate);
        this.addOnStartup(&onAppStartup);
        this.addOnShutdown(&onAppShutdown);
        GVariant param = new GVariant([new GVariant("None"), new GVariant("None"), new GVariant("None")]);
        trace("Registering command action with type " ~ param.getType().peekString());
        registerAction(this, ACTION_PREFIX, ACTION_COMMAND, null, &executeCommand, param.getType(), param);
        terminix = this;
    }
    
    /**
     * Executes a command by invoking the command action.
     * This is used to invoke a command on a remote instance of
     * the GTK Application leveraging the ability for the remote
     * instance to trigger actions on the primary instance.
     *
     * See https://wiki.gnome.org/HowDoI/GtkApplication
     */
    void executeCommand(string command, string terminalID, string cmdLine) {
        GVariant[] param = [new GVariant(command), new GVariant(terminalID), new GVariant(cmdLine)];
        activateAction(ACTION_COMMAND, new GVariant(param));
    }

    void addAppWindow(AppWindow window) {
        appWindows ~= window;
        //GTK add window
        addWindow(window);
    }
    
    void removeAppWindow(AppWindow window) {
        gx.util.array.remove(appWindows, window);
        removeWindow(window);
    }
    
    void addProfileWindow(ProfileWindow window) {
        profileWindows ~= window;
        //GTK add window
        addWindow(window);
    }
    
    void removeProfileWindow(ProfileWindow window) {
        gx.util.array.remove(profileWindows, window);
        //GTK remove window
        removeWindow(window);
    }
    
    /**
    * This searches across all Windows to find
    * a widget that matches the UUID specified. At the
    * moment this would be a session or a terminal.
    *
    * This is used for any operations that span windows, at 
    * the moment there is just one, dragging a terminal from
    * one Window to the next.
    *
    * TODO - Convert this into a template to eliminate casting
    *        by callers
    */
    Widget findWidgetForUUID(string uuid) {

        foreach(window; appWindows) {
            trace("Finding widget " ~ uuid);
            trace("Checking app window");
            Widget result = window.findWidgetForUUID(uuid);
            if (result !is null) {
                return result;
            }
        }
        return null;
    }
    
    void presentPreferences() {
        //Check if preference window already exists
        if (preferenceWindow !is null) {
            preferenceWindow.present();
            return;
        }
        //Otherwise create it and save the ID
        preferenceWindow = new PreferenceWindow(this);
        addWindow(preferenceWindow);
        preferenceWindow.addOnDelete(delegate(Event, Widget) {
            preferenceWindow = null;
            removeWindow(preferenceWindow);
            return false;
        });
        preferenceWindow.showAll();
    }
    
    void closeProfilePreferences(ProfileInfo profile) {
        foreach(window; profileWindows) {
            if (window.uuid == profile.uuid) {
                window.destroy();
                return;
            }
        }
    }
    
    void presentProfilePreferences(ProfileInfo profile) {
        foreach(window; profileWindows) {
            if (window.uuid == profile.uuid) {
                window.present();
                return;
            }
        }
        ProfileWindow window = new ProfileWindow(this, profile);
        window.showAll();
    }
    
    bool testVTEConfig() {
        return !warnedVTEConfigIssue && gsGeneral.getBoolean(SETTINGS_WARN_VTE_CONFIG_ISSUE_KEY);
    }
    
    /**
     * Even those these are parameters passed on the command-line
     * they are used by the terminal when it is created as a global
     * override.
     *
     * Originally I was passing command line parameters to the terminal
     * via the heirarchy App > AppWindow > Session > Terminal but this
     * is unwiedly. It's also not feasible when supporting using the
     * command line to create terminals in the current instance since
     * that uses actions and it's not feasible to pass these via the
     * action mechanism.
     *
     * When a terminal is created, it will check this global overrides and
     * use it where applicaable. The application is responsible for setiing
     * and clearing these overrides around the terminal creation. Since GTK
     * is single threaded this works fine.
     */
    CommandParameters getGlobalOverrides() {
        return cp;
    }
    
    /**
     * Shows a dialog when a VTE configuration issue is detected.
     * See Issue #34 and https://github.com/gnunn1/terminix/wiki/VTE-Configuration-Issue
     * for more information.
     */
    void warnVTEConfigIssue() {
        if (testVTEConfig()) {
            warnedVTEConfigIssue = true;
            string msg = "There appears to be an issue with the configuration of the terminal.\n" ~
                         "This issue is not serious, but correcting it will improve your experience.\n" ~
                         "Click the link below for more information:";
            string title = "<span weight='bold' size='larger'>" ~ _("Configuration Issue Detected") ~ "</span>";
            MessageDialog dlg = new MessageDialog(getActiveWindow(), DialogFlags.MODAL, MessageType.WARNING, ButtonsType.OK, null, null);
            scope(exit) {dlg.destroy();}
            with (dlg) {
                setTransientFor(getActiveWindow());
                setMarkup(title);
                getMessageArea().setMarginLeft(0);
                getMessageArea().setMarginRight(0);
                getMessageArea().add(new Label(_(msg)));
                getMessageArea().add(new LinkButton("https://github.com/gnunn1/terminix/wiki/VTE-Configuration-Issue"));
                CheckButton cb = new CheckButton(_("Do not show this message again"));
                getMessageArea().add(cb);
                setImage(new Image("dialog-warning", IconSize.DIALOG));
                showAll();
                run();
                if (cb.getActive()) {
                    gsGeneral.setBoolean(SETTINGS_WARN_VTE_CONFIG_ISSUE_KEY, false);
                }
            }
        }
    }
}