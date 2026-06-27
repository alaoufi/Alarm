package com.mudhakkarati.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// مزوّد ويدجت الشاشة الرئيسية: يعرض الملاحظة المثبّتة/الأخيرة ويفتح التطبيق عند الضغط.
class HomeWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.home_widget_layout).apply {
                val title = widgetData.getString("widget_title", "Alaoufi Notes") ?: "Alaoufi Notes"
                val note = widgetData.getString("widget_note", "لا توجد ملاحظات بعد")
                    ?: "لا توجد ملاحظات بعد"

                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_note, note)

                // الضغط على الويدجت يفتح التطبيق.
                val openApp = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_title, openApp)
                setOnClickPendingIntent(R.id.widget_note, openApp)
                setOnClickPendingIntent(R.id.widget_add, openApp)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
