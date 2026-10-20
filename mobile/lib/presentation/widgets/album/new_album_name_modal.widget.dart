import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';

class NewAlbumModalResult {
  final String title;
  final String? description;

  const NewAlbumModalResult({
    required this.title,
    this.description,
  });
}

class NewAlbumNameModal extends StatefulWidget {
  const NewAlbumNameModal({
    super.key,
    this.withDescription = true,
    this.initialTitle,
    this.initialDescription,
  });

  final bool withDescription;
  final String? initialTitle;
  final String? initialDescription;

  @override
  State<NewAlbumNameModal> createState() => _NewAlbumNameModalState();
}

class _NewAlbumNameModalState extends State<NewAlbumNameModal> {
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.initialTitle);
    descriptionController = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t.create_album, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.t.album_name,
                hintText: context.t.name,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (widget.withDescription) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: descriptionController,
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(
                  labelText: context.t.add_a_description,
                  hintText: context.t.add_a_description,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(null),
          child: Text(
            context.t.cancel,
            style: TextStyle(color: Colors.red[300], fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: () {
            final title = nameController.text.trim();
            if (title.isEmpty) {
              return;
            }
            if (widget.withDescription) {
              final desc = descriptionController.text.trim();
              context.pop(
                NewAlbumModalResult(
                  title: title,
                  description: desc.isEmpty ? null : desc,
                ),
              );
            } else {
              context.pop(title);
            }
          },
          child: Text(
            context.t.create_album,
            style: TextStyle(color: context.primaryColor, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
