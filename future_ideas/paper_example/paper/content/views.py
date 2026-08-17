from rest_framework import viewsets
from .models import Paper
from .serializers import PaperSerializer


class PaperViewSet(viewsets.ModelViewSet):
    serializer_class = PaperSerializer
    queryset = Paper.objects.all()

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)
