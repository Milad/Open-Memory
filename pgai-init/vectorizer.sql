CREATE EXTENSION IF NOT EXISTS ai CASCADE;

SELECT ai.create_vectorizer(
    'public.memory_nodes'::regclass,
    name => 'memory_nodes_embedding_vectorizer',
    loading => ai.loading_column('content'),
    embedding => ai.embedding_voyageai('voyage-3', 1024, api_key_name => 'VOYAGE_API_KEY'),
    chunking => ai.chunking_none(),
    destination => ai.destination_column('embedding'),
    enqueue_existing => true,
    if_not_exists => true
);
