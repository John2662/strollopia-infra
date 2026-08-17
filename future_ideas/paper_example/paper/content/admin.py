from django.contrib import admin

from content.models import (
    Tag,
    Category,
    Paper,
    Page,
    Paragraph,
    Language
)


class CategoryAdmin(admin.ModelAdmin):
    list_display = ('id', 'name')
    search_fields = ('name',)


class TagAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'user')
    search_fields = ('name',)
    autocomplete_fields = ('user',)

    def get_form(self, request, obj=None, **kwargs):
        if not request.user.is_superuser:
            # Exclude the "user" field for non-admin users
            self.exclude = ("user",)
        else:
            # Make sure superusers can see all fields
            self.exclude = None
        return super().get_form(request, obj, **kwargs)

    def save_model(self, request, obj, form, change):
        if not request.user.is_superuser:
            # Set the "user" field to the current user's owning organization
            obj.user = request.user
        super().save_model(request, obj, form, change)

    # def get_queryset(self, request):
    #     qs = super().get_queryset(request)
    #     if request.user.is_superuser:
    #         return qs
    #     return qs.filter(user__owning_org=request.user.owning_org)

    def get_readonly_fields(self, request, obj=None):
        if obj:
            return ["user"]
        else:
            return []


class LanguageAdmin(admin.ModelAdmin):
    list_display = ('id', 'name')
    readonly_fields = ('name',)
    # autocomplete_fields = ('owner',)
    search_fields = ('name',)

    # def get_queryset(self, request):
    #     qs = super().get_queryset(request)
    #     if request.user.is_superuser:
    #         return qs
    #     return qs.filter(owner__user__owning_org=request.user.owning_org)

    def get_readonly_fields(self, request, obj=None):
        if obj:
            return ["paper", "name"]
        else:
            return []


class PaperAdmin(admin.ModelAdmin):
    search_fields = ('allowed_users',)
    autocomplete_fields = ('allowed_viewers', 'user', 'tags')
    list_display = ('id', 'is_public')


class PageAdmin(admin.ModelAdmin):
    list_display = ('id', 'owning_paper')


class ParagraphAdmin(admin.ModelAdmin):
    list_display = ('id', 'page')


admin.site.register(Language, LanguageAdmin)
admin.site.register(Tag, TagAdmin)
admin.site.register(Paragraph, ParagraphAdmin)
admin.site.register(Paper, PaperAdmin)
admin.site.register(Page, PageAdmin)
admin.site.register(Category, CategoryAdmin)
