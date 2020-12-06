#include <cairo.h>
#include <gtk/gtk.h>

#ifdef cairo_implementation
	#define IMPL(body) body
	#define IMPLONLY(body) body
#else
	#define IMPL(body) ;
	#define IMPLONLY(body)
#endif

IMPLONLY(

void zig_on_draw_event(cairo_t *cr);
gboolean zig_on_keypress_event(GdkEventKey *widget, GtkIMContext *im_context);
void zig_on_keyrelease_event(GdkEventKey *widget);

static gboolean on_draw_event(GtkWidget *widget, cairo_t *cr, gpointer user_data) {
	zig_on_draw_event(cr);
	return FALSE;
}

static gboolean on_keypress_event(GtkWidget *widget, GdkEventKey *event, GtkIMContext *im_context) {
	// return gtk_im_context_filter_keypress(im_context, event);
	return zig_on_keypress_event(event, im_context);
}

static gboolean on_keyrelease_event(GtkWidget *widget, GdkEventKey *event, gpointer data) {
	zig_on_keyrelease_event(event);
	return TRUE; // = stop propagation. ok as long as we don't use any gtk widgets
}

static void destroy(GtkWidget *widget, gpointer data) {
    gtk_main_quit ();
}


// https://developer.gnome.org/gtk3/stable/GtkIMContext.html
void zig_on_commit_event(GtkIMContext *context, gchar *str, gpointer user_data);
gboolean zig_on_delete_surrounding_event(GtkIMContext *context, gint offset, gint n_chars, gpointer user_data);
void zig_on_preedit_changed_event(GtkIMContext *context, gpointer user_data);
gboolean zig_on_retrieve_surrounding_event(GtkIMContext *context, gpointer user_data);

)

// maybe switch to gdk instead? give up on gtk?

int start_gtk(int argc, char *argv[])
IMPL({
	gtk_init(&argc, &argv);

	GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);

	gtk_widget_add_events(window, GDK_KEY_PRESS_MASK);
	gtk_widget_add_events(window, GDK_KEY_RELEASE_MASK);
	
	GtkIMContext *im_context = gtk_im_multicontext_new();
	GdkWindow *gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
	gtk_im_context_set_client_window(im_context, gdk_window);

	GtkWidget *darea = gtk_drawing_area_new();
	gtk_container_add(GTK_CONTAINER(window), darea);

	g_signal_connect(G_OBJECT(darea), "draw", G_CALLBACK(on_draw_event), NULL); 
	g_signal_connect(window, "destroy", G_CALLBACK(destroy), NULL);
	g_signal_connect(G_OBJECT(window), "key_press_event", G_CALLBACK(on_keypress_event), im_context);
	g_signal_connect(G_OBJECT(window), "key_release_event", G_CALLBACK(on_keyrelease_event), NULL);
	
	g_signal_connect(im_context, "commit", G_CALLBACK(zig_on_commit_event), NULL);
	//g_signal_connect(im_context, "delete-surrounding", G_CALLBACK(zig_on_delete_surrounding_event), NULL);
	//g_signal_connect(im_context, "preedit-changed", G_CALLBACK(zig_on_preedit_changed_event), NULL);
	//g_signal_connect(im_context, "retrieve-surrounding", G_CALLBACK(zig_on_retrieve_surrounding_event), NULL);

	gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
	gtk_window_set_default_size(GTK_WINDOW(window), 400, 90); 
	gtk_window_set_title(GTK_WINDOW(window), "GTK window");

	gtk_widget_show_all(window);
	gtk_im_context_focus_in(im_context);

	gtk_main();

	return 0;
})