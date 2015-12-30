﻿﻿/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
 * distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
module gx.terminix.application;

import std.experimental.logger;
import std.format;
import std.path;
import std.variant;

import gio.ActionMapIF;
import gio.Menu;
import gio.MenuModel;
import gio.Settings : GSettings = Settings;
import gio.SimpleAction;

import gtk.AboutDialog;
import gtk.Application;
import gtk.Dialog;
import gtk.Settings;
import gtk.Widget;
import gtk.Window;

import gx.gtk.actions;
import gx.gtk.util;
import gx.i18n.l10n;
import gx.terminix.appwindow;
import gx.terminix.constants;
import gx.terminix.preferences;
import gx.terminix.prefwindow;

class Terminix : Application {

private:

	enum ACTION_PREFIX = "app";

	enum ACTION_NEW_WINDOW = "new-window";
	enum ACTION_NEW_SESSION = "new-session";
	enum ACTION_PREFERENCES = "preferences";
	enum ACTION_ABOUT = "about";
	enum ACTION_QUIT = "quit";

	uint prefId = 0;
	GSettings gsShortcuts;
	GSettings gsGeneral;

	/**
     * Load and register binary resource file and add css files as providers
     */
	void loadResources() {
		//Load resources
		if (findResource(APPLICATION_RESOURCES, true)) {
			foreach (cssFile; APPLICATION_CSS_RESOURCES) {
				string cssURI = buildPath(APPLICATION_RESOURCE_ROOT, cssFile);
				if (!addCssProvider(cssURI)) {
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
		Menu appMenu = new Menu();

		registerAction(this, ACTION_PREFIX, ACTION_NEW_SESSION, null, delegate(Variant, SimpleAction) { this.onCreateNewSession(); });

		registerAction(this, ACTION_PREFIX, ACTION_NEW_WINDOW, null, delegate(Variant, SimpleAction) { this.onCreateNewWindow(); });

		registerAction(this, ACTION_PREFIX, ACTION_PREFERENCES, null, delegate(Variant, SimpleAction) { this.onShowPreferences(); });

		registerAction(this, ACTION_PREFIX, ACTION_ABOUT, null, delegate(Variant, SimpleAction) { this.onShowAboutDialog(); });

		registerAction(this, ACTION_PREFIX, ACTION_QUIT, null, delegate(Variant, SimpleAction) { foreach (Window window; getAppWindows()) {
			window.close();}  });

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
			//Check if preference window already exists
			if (prefId != 0) {
				Window window = getWindowById(prefId);
				if (window) {
					window.present();
					return;
				}
			}
			//Otherwise create it and save the ID
			PreferenceWindow window = new PreferenceWindow(this);
			addWindow(window);
			window.showAll();
			prefId = window.getId();
		}

		/**
     * Shows the about dialog.
     * 
	 * This code adapted from grestful (https://github.com/Gert-dev/grestful)
     */
		void onShowAboutDialog() {
			AboutDialog dialog;

			with (dialog = new AboutDialog()) {
				setDestroyWithParent(true);
				//setTransientFor(this.window);
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
				//addCreditSection(_("Credits"), [])

				addOnResponse(delegate(int responseId, Dialog sender) {
					if (responseId == ResponseType.CANCEL || responseId == ResponseType.DELETE_EVENT)
						sender.hideOnDelete(); // Needed to make the window closable (and hide instead of be deleted).
				});

				present();
			}
		}

		void createAppWindow() {
			AppWindow window = new AppWindow(this);
			this.addWindow(window);
			window.showAll();
		}

		Window[] getAppWindows() {
			return getWindows().toArray!Window();
		}

		void onAppActivate(GioApplication app) {
			trace("Activate App Signal");
			createAppWindow();
		}

		void onAppStartup(GioApplication app) {
			trace("Startup App Signal");
			loadResources();
			setApplication(this);
			gsShortcuts = new GSettings(SETTINGS_PROFILE_KEY_BINDINGS_ID);
			gsShortcuts.addOnChanged(delegate(string key, Settings) {
				trace("Updating shortcut '" ~ keyToDetailedActionName(key) ~ "' to '" ~ gsShortcuts.getString(key) ~ "'");
				setAccelsForAction(keyToDetailedActionName(key), [gsShortcuts.getString(key)]);
				string[] values = getAccelsForAction(keyToDetailedActionName(key));
				foreach (value;
				values) {
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
			setApplication(null);
		}

		void applyPreferences() {
			Settings.getDefault().setProperty(GTK_APP_PREFER_DARK_THEME, (SETTINGS_THEME_VARIANT_DARK_VALUE == gsGeneral.getString(SETTINGS_THEME_VARIANT_KEY)));
		}

	public:

		this() {
			super(APPLICATION_ID, ApplicationFlags.FLAGS_NONE);

			this.addOnActivate(&onAppActivate);
			this.addOnStartup(&onAppStartup);
			this.addOnShutdown(&onAppShutdown);

		}
	}