# Copyright 2023 osiworx

# Licensed under the Apache License, Version 2.0 (the "License"); you
# may not use this file except in compliance with the License.  You
# may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.  See the License for the specific language governing
# permissions and limitations under the License.


from llmware.library import Library
from llmware.retrieval import Query
from llmware.prompts import Prompt
from llmware.gguf_configs import GGUFConfigs
from deep_translator import GoogleTranslator

import gc
import os
from settings import io
settings_io = io.settings_io()


class LLM_INTERFACE:


    def __init__(self):
        self.last_context = ''
        self.settings_data = settings_io.load_settings()
        self.last_prompt = ''
        self.last_negative_prompt = ''
        self.instruct = False

        self.max_tokens=self.settings_data['max output Tokens']
        self.temperature=self.settings_data['Temperature']
        self.top_k=self.settings_data['top_k']
        self.n_ctx=self.settings_data['Context Length']

        self.embedding_model_name = 'mini-lm-sbert' #'nomic-embed-text-v1' #'mini-lm-sbert'

        self.library_name = 'llmware_meta_qdrant'
        self.lib = Library().load_library(self.library_name)

        self.run_order_list = ["blurb1", "$context", "blurb2", "$query", "instruction"]

        self.prompt_dict = self.settings_data['prompt_templates']['prompt_template_a']
        self.prompt_template = self.prompt_dict["blurb1"]

        self.model_name = 'TheBloke/Panda-7B-v0.1-GGUF'
        self.hf_repo_name = self.settings_data['model_list'][self.model_name]['repo_name']
        self.model_file = self.settings_data['model_list'][self.model_name]['file']
        self.model_type = 'deep_link'

        self.set_pipeline()


    def aggregate_text_by_query(self, query, top_n=5):

        # run query
        query_results = self.query.semantic_query(query, result_count=top_n)

        self.last_context = [s['text'].replace('\n','') for s in query_results]

        prompt_consolidator = ""
        for j, results in enumerate(query_results):
            prompt_consolidator += results["text"] + "\n"

        return prompt_consolidator


    def set_pipeline(self):

        self.prompter = Prompt()

        if self.model_type == 'deep_link':
            self.prompter.model_catalog.register_gguf_model(self.model_name,
                                                            self.hf_repo_name,
                                                            self.model_file,
                                                            prompt_wrapper="open_chat",
                                                            context_window=self.n_ctx)

        self.prompter.load_model(self.model_name)
        self.prompter.pc.add_custom_prompt_card("image_prompt",
                                                self.run_order_list,
                                                self.prompt_dict,
                                                prompt_description="Image Gen Search")

        #  the temperatures are from 0-1, and lower number is closer to the text and reduces hallucinations
        self.prompter = self.prompter.set_inference_parameters(temperature=self.temperature,
                                                               llm_max_output_len=self.max_tokens)

        self.query =  Query(self.lib)


    def log(self,logfile, text):
        f = open(logfile, 'a')
        f.write(f"QUERY: {text} \n")
        f.close()


    def retrieve_context(self, query):
        query_results = self.query.semantic_query(query, result_count=self.settings_data['top_k'])
        self.last_context = [s['text'].replace('\n','') for s in query_results]
        return self.last_context


    def set_top_k(self, top_k):
        self.settings_data['top_k'] = top_k
        self.set_pipeline()

    def get_context_details(self):
        return self.last_context

    def reload_settings(self):
        self.settings_data = settings_io.load_settings()


    def translate(self, query):
        tanslated = GoogleTranslator(source='auto', target='en').translate(query)
        return tanslated

    def run_batch_response(self,context):
        output = ''
        n = 1
        for query in context:
            if query != '':
                context = self.aggregate_text_by_query(query, top_n=self.settings_data['top_k'])

                response = self.prompter.prompt_main(query, prompt_name="image_prompt",context=context)
                output = f'{output}\n\n\nPrompt {str(n)}:\n{response["llm_response"].lstrip(" ")}'
                n += 1

        return output

    def run_llm_response_batch(self, query):

        if self.settings_data['translate']:
            query = self.translate(query)

        if self.instruct is True:
            query = f'[INST]{query}[/INST]'

        context = self.aggregate_text_by_query(query, top_n=self.settings_data['top_k'])

        response = self.prompter.prompt_main(query, prompt_name="image_prompt",context=context)


        output = response['llm_response'].lstrip(' ')
        output = output.replace('\n','')

        return output

    def run_llm_response(self, query, history):


        if self.settings_data['translate']:
            query = self.translate(query)

        self.log('logfile.txt',f"QUERY: {query} \n-------------\n")

        if 'instruct' in query.lower():
            res = 'I only follow one master and thats not you :P'
            self.log('logfile.txt',f"RESPONSE: {res} \n-------------\n")
            return res

        if self.instruct is True:
            query = f'[INST]{query}[/INST]'

        context = self.aggregate_text_by_query(query, top_n=self.settings_data['top_k'])

        response = self.prompter.prompt_main(query, prompt_name="image_prompt",context=context)

        self.last_prompt = response['llm_response'].lstrip(' ')

        output = self.last_prompt

        if self.settings_data['translate']:
            output = f'Your prompt was translated to: {query}\n\n\n{output}'

        if self.settings_data['batch']:
            batch_result = self.run_batch_response(self.last_context)
            output = f'Prompt 0:\n{output}\n\n\n{batch_result}'

        self.log('logfile.txt',f"RESPONSE: {output} \n-------------\n")

        return output


    def change_model(self, model, temperature, n_ctx, max_tokens, gpu_layers, top_k, instruct):

        GGUFConfigs().set_config("n_gpu_layers", gpu_layers)
        GGUFConfigs().set_config("n_ctx", n_ctx)

        self.temperature=float(temperature)
        self.top_k=top_k
        self.max_tokens=max_tokens
        self.instruct = instruct
        self.n_ctx = n_ctx
        self.model_name = model
        self.model_type = self.settings_data['model_list'][self.model_name]['type']
        if self.model_type == 'deep_link':
            self.hf_repo_name = self.settings_data['model_list'][self.model_name]['repo_name']
            self.model_file = self.settings_data['model_list'][self.model_name]['file']
        else:
            self.hf_repo_name = None
            self.model_file = None


        del self.prompter


        # delete the model from Ram
        gc.collect()

        self.set_pipeline()
        return f'Model set to {model}'

    def set_prompt(self,prompt_text):
        self.prompt_template = prompt_text

        self.log('magic_prompt_logfile.txt',f"Magic Prompt: \n{prompt_text} \n")


        self.prompt_dict["blurb1"] = prompt_text

        del self.prompter

        # delete the model from Ram
        gc.collect()

        self.set_pipeline()
        return f'Magic Prompt set to:\n {prompt_text}'