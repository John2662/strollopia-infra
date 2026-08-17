from django.conf import settings
from django.db import models


class Tag(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
    )
    name = models.CharField(max_length=255)


class Category(models.Model):
    name = models.CharField(max_length=255, unique=True)


class Paper(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
    )
    title = models.CharField(max_length=256)
    paper_description = models.CharField(max_length=256)
    is_public = models.BooleanField(default=False)
    allowed_viewers = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        related_name='allowed_viewers',
        blank=True
    )
    tags = models.ManyToManyField('Tag', blank=True)


class Page(models.Model):
    owning_paper = models.ForeignKey(
        Paper,
        related_name='pages',
        on_delete=models.CASCADE
    )
    name = models.CharField(max_length=256)
    page_number = models.IntegerField()
    categories = models.ManyToManyField('Category', blank=True)
    page_description = models.CharField(max_length=256)
    # Generic fields
    generic_bool_01 = models.BooleanField(default=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['owning_paper', 'name'],
                name='unique_page'
            )
        ]
        pass


class Paragraph(models.Model):
    page = models.ForeignKey(
        Page,
        related_name='paragraphs',
        on_delete=models.CASCADE
    )
    content = models.CharField(max_length=256)


class Language(models.Model):
    paper = models.ForeignKey(
        Paper,
        related_name='languages',
        on_delete=models.CASCADE
    )
    name = models.CharField(max_length=256)
