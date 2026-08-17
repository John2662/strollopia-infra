from rest_framework import serializers
from .models import Paper, Page, Paragraph, Tag, Language, Category

class ParagraphSerializer(serializers.ModelSerializer):
    class Meta:
        model = Paragraph
        fields = ['id', 'content']

class PageSerializer(serializers.ModelSerializer):
    paragraphs = ParagraphSerializer(many=True)
    categories = serializers.PrimaryKeyRelatedField(queryset=Category.objects.all(), many=True)

    class Meta:
        model = Page
        fields = ['id', 'page_number', 'categories', 'page_description', 'paragraphs']

class TagSerializer(serializers.ModelSerializer):
    class Meta:
        model = Tag
        fields = ['id', 'name']

class LanguageSerializer(serializers.ModelSerializer):
    class Meta:
        model = Language
        fields = ['id', 'name']

class PaperSerializer(serializers.ModelSerializer):
    pages = PageSerializer(many=True)
    tags = serializers.ListSerializer(child=serializers.CharField())
    languages = serializers.ListSerializer(child=serializers.CharField())

    class Meta:
        model = Paper
        fields = ['id', 'title', 'paper_description', 'is_public', 'tags', 'languages', 'pages']

    def create(self, validated_data):
        tags_data = validated_data.pop('tags')
        languages_data = validated_data.pop('languages')
        pages_data = validated_data.pop('pages')

        paper = Paper.objects.create(**validated_data)

        # Create or get tags
        for tag_name in tags_data:
            tag, created = Tag.objects.get_or_create(user=self.context['request'].user, name=tag_name)
            paper.tags.add(tag)

        # Create languages
        for language_name in languages_data:
            Language.objects.create(paper=paper, name=language_name)

        # Create pages and paragraphs
        for page_data in pages_data:
            paragraphs_data = page_data.pop('paragraphs')
            categories_data = page_data.pop('categories')
            page = Page.objects.create(paper=paper, **page_data)
            page.categories.set(categories_data)
            for paragraph_data in paragraphs_data:
                Paragraph.objects.create(page=page, **paragraph_data)

        return paper

    def update(self, instance, validated_data):
        tags_data = validated_data.pop('tags')
        languages_data = validated_data.pop('languages')
        pages_data = validated_data.pop('pages')

        instance.title = validated_data.get('title', instance.title)
        instance.paper_description = validated_data.get('paper_description', instance.paper_description)
        instance.is_public = validated_data.get('is_public', instance.is_public)
        instance.save()

        # Update tags
        instance.tags.clear()
        for tag_name in tags_data:
            tag, created = Tag.objects.get_or_create(user=self.context['request'].user, name=tag_name)
            instance.tags.add(tag)

        # Update languages
        instance.languages.all().delete()
        for language_name in languages_data:
            Language.objects.create(paper=instance, name=language_name)

        # Update pages and paragraphs
        for page_data in pages_data:
            page_id = page_data.get('id')
            if page_id:
                page = Page.objects.get(id=page_id, paper=instance)
                page.page_number = page_data.get('page_number', page.page_number)
                page.page_description = page_data.get('page_description', page.page_description)
                page.save()

                # Update categories
                categories_data = page_data.pop('categories')
                page.categories.set(categories_data)

                # Update paragraphs
                paragraphs_data = page_data.pop('paragraphs')
                existing_paragraph_ids = [p.id for p in page.paragraphs.all()]
                for paragraph_data in paragraphs_data:
                    paragraph_id = paragraph_data.get('id')
                    if paragraph_id and paragraph_id in existing_paragraph_ids:
                        paragraph = Paragraph.objects.get(id=paragraph_id, page=page)
                        paragraph.content = paragraph_data.get('content', paragraph.content)
                        paragraph.save()
                        existing_paragraph_ids.remove(paragraph_id)
                    else:
                        Paragraph.objects.create(page=page, **paragraph_data)

                # Delete removed paragraphs
                Paragraph.objects.filter(id__in=existing_paragraph_ids).delete()
            else:
                # Create new page
                paragraphs_data = page_data.pop('paragraphs')
                categories_data = page_data.pop('categories')
                page = Page.objects.create(paper=instance, **page_data)
                page.categories.set(categories_data)
                for paragraph_data in paragraphs_data:
                    Paragraph.objects.create(page=page, **paragraph_data)

        return instance

