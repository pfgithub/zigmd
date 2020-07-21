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
void zig_on_keypress_event(GdkEventKey *widget);

static gboolean on_draw_event(GtkWidget *widget, cairo_t *cr, gpointer user_data) {
	zig_on_draw_event(cr);
	return FALSE;
}

static gboolean on_keypress_event(GtkWidget *widget, GdkEventKey *event, gpointer data) {
	zig_on_keypress_event(event);
	return TRUE; // = stop propagation. ok as long as we don't use any gtk widgets
}

static void destroy(GtkWidget *widget, gpointer data) {
    gtk_main_quit ();
}

)

// maybe switch to gdk instead? give up on gtk?

int start_gtk(int argc, char *argv[])
IMPL({
	GtkWidget *window;
	GtkWidget *darea;

	gtk_init(&argc, &argv);

	window = gtk_window_new(GTK_WINDOW_TOPLEVEL);

	gtk_widget_add_events(window, GDK_KEY_PRESS_MASK);

	darea = gtk_drawing_area_new();
	gtk_container_add(GTK_CONTAINER(window), darea);

	g_signal_connect(G_OBJECT(darea), "draw", G_CALLBACK(on_draw_event), NULL); 
	g_signal_connect(window, "destroy", G_CALLBACK(destroy), NULL);
	g_signal_connect(G_OBJECT(window), "key_press_event", G_CALLBACK(on_keypress_event), NULL);

	gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
	gtk_window_set_default_size(GTK_WINDOW(window), 400, 90); 
	gtk_window_set_title(GTK_WINDOW(window), "GTK window");

	gtk_widget_show_all(window);

	gtk_main();

	return 0;
})